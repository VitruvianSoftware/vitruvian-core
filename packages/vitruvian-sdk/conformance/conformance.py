#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
"""Plays the app's side of the Vitruvian tool protocol, versions 1 and 2, to a tool.

    python3 conformance.py <tool folder> [--via PROGRAM] [--expect-refusal]

`<tool folder>` holds a vitruvian-tool.json. The program its manifest names is
started the way the app starts it: in a folder of its own, with this script on
its standard input and output. `--via` starts it through another program, for
example a Python interpreter, when the file cannot be run by itself.

Six things are checked, in order, and the first failure stops the run:

  handshake   the tool answers `initialize` first, with a version offered
  a command   its first command is run and answered
  unknown     a command it does not have is answered with a failure
  a panel     for a tool of protocol 2: its first panel the app draws is
              opened and answered with a page; its first button is tapped and
              answered with a new page; the panel is closed
  refusals    the command is run again with every request the tool makes
              refused, and is still answered
  shutdown    after `shutdown` and the end of its input, the tool exits with 0,
              and what it wrote on the way out is messages too

Every line the tool writes must be one JSON-RPC 2.0 message, at most 1 MB,
and a message the protocol has must carry the params the protocol gives it.
A page sent with `ui/render` must be for a panel the manifest declares.
While a command runs, the script answers the tool's requests as the app would:
a service the manifest's `uses` does not list is refused with -32001.

It needs Python 3 and nothing else, and it does not need the app. It exits
with 0 when every check passed.
"""

import argparse
import json
import os
import queue
import subprocess
import sys
import tempfile
import threading
import time

MAX_LINE_BYTES = 1_048_576
FIRST_ANSWER_SECONDS = 10
ANSWER_SECONDS = 2
EXIT_SECONDS = 2

MAX_TREE_BYTES = 262_144
MAX_BLOCKS = 200
NEEDS_ID = ("button", "toggle", "field", "list")
VERSIONS = ["1", "2"]

INVALID_PARAMS = -32602
METHOD_NOT_FOUND = -32601
NOT_IN_USES = -32001
UNAVAILABLE = -32004

# Each request a tool may make: the entry of `uses` it needs, and what the app
# answers once it has done the work.
SERVICES = {
    "notify/hud": ("notify", {}),
    "notify/beep": ("notify", {}),
    "open/url": ("open", {"opened": True}),
    "clipboard/readText": ("clipboard.read", {"text": "conformance"}),
    "clipboard/writeText": ("clipboard.write", {"written": True}),
    "keystrokes/paste": ("keystrokes", {}),
    "keystrokes/pressMenuItem": ("keystrokes", {"pressed": True}),
    "processes/terminate": ("processes", {}),
    "storage/get": ("storage", None),
    "storage/set": ("storage", {}),
    "ui/badge": ("notify", {}),
}


def is_text(value):
    return isinstance(value, str)


def is_flag(value):
    return isinstance(value, bool)


def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def is_whole(value):
    return is_number(value) and float(value).is_integer()


def is_saved(value):
    """What a preference may hold: text, yes or no, or a number."""
    return is_text(value) or is_flag(value) or is_number(value)


def is_equivalent(value):
    return (
        isinstance(value, dict)
        and is_text(value.get("character"))
        and list_of(lambda held: held in ("shift", "option", "control"))(
            value.get("modifiers")
        )
    )


def list_of(check):
    return lambda value: isinstance(value, list) and all(map(check, value))


def is_count(value):
    return is_whole(value) and value >= 0


def is_block(value):
    """A block: a kind, and an id where its kind needs one. A kind this
    script does not know is a later version's, and is fine."""
    return (
        isinstance(value, dict)
        and is_text(value.get("type"))
        and (value["type"] not in NEEDS_ID or is_text(value.get("id")))
    )


def is_tree(value):
    """A page: at most 200 blocks, and at most 262,144 bytes as JSON."""
    if not isinstance(value, dict) or not isinstance(value.get("blocks"), list):
        return False
    if len(value["blocks"]) > MAX_BLOCKS or not all(map(is_block, value["blocks"])):
        return False
    return len(json.dumps(value, separators=(",", ":")).encode()) <= MAX_TREE_BYTES


# The params each message a tool sends must carry. Anything more is ignored,
# and so is a message the protocol does not have.
PARAMS = {
    "commands/state": {"runnable": list_of(is_text)},
    "log": {"message": is_text},
    "notify/hud": {"icon": is_text, "message": is_text},
    "notify/beep": {},
    "open/url": {"url": is_text},
    "clipboard/readText": {},
    "clipboard/writeText": {"text": is_text},
    "keystrokes/paste": {"text": is_text},
    "keystrokes/pressMenuItem": {"equivalents": list_of(is_equivalent)},
    "processes/terminate": {"pid": is_whole, "name": is_text, "force": is_flag},
    "storage/get": {"key": is_text},
    "storage/set": {"key": is_text, "value": is_saved},
    "ui/render": {"panel": is_text, "tree": is_tree},
    "ui/badge": {},
}

# The params a message may carry, and must carry rightly when it does.
OPTIONAL_PARAMS = {
    "ui/badge": {"count": is_count, "dot": is_flag},
}


class Failure(Exception):
    """A check the tool did not pass."""


def check_params(message):
    """A Failure when a message the protocol has does not carry its params."""
    params = message.get("params", {})
    for name, check in PARAMS.get(message["method"], {}).items():
        if name not in params or not check(params[name]):
            raise Failure(
                f"{message['method']} with params that are not its own: {params!r}"
            )
    for name, check in OPTIONAL_PARAMS.get(message["method"], {}).items():
        if name in params and not check(params[name]):
            raise Failure(
                f"{message['method']} with params that are not its own: {params!r}"
            )


def is_id(value):
    return isinstance(value, (int, str)) and not isinstance(value, bool)


def kind_of(message):
    """request, notice, result or failure; a Failure for anything else."""
    if not isinstance(message, dict) or message.get("jsonrpc") != "2.0":
        raise Failure(f"a line that is not a JSON-RPC 2.0 message: {message!r}")
    if "method" in message:
        answers = "result" in message or "error" in message
        if not isinstance(message["method"], str) or answers:
            raise Failure(f"a message that is not well formed: {message!r}")
        if not isinstance(message.get("params", {}), dict):
            raise Failure(f"params that are not an object: {message!r}")
        if "id" not in message:
            return "notice"
        if is_id(message["id"]):
            return "request"
    elif "error" in message and "result" not in message:
        error = message["error"]
        if (
            isinstance(error, dict)
            and isinstance(error.get("code"), int)
            and not isinstance(error.get("code"), bool)
            and isinstance(error.get("message"), str)
            and (is_id(message.get("id", False)) or message.get("id", False) is None)
        ):
            return "failure"
    elif "result" in message and is_id(message.get("id")):
        return "result"
    raise Failure(f"a message that is not well formed: {message!r}")


class Link:
    """The tool's process, with its standard output read a line at a time."""

    def __init__(self, command, folder):
        self.process = subprocess.Popen(
            command, cwd=folder, stdin=subprocess.PIPE, stdout=subprocess.PIPE
        )
        self.lines = queue.Queue()
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()

    def _read(self):
        while True:
            line = self.process.stdout.readline(MAX_LINE_BYTES + 2)
            self.lines.put(line)
            if not line:
                return

    def send(self, message):
        try:
            self.process.stdin.write(
                json.dumps(message, separators=(",", ":")).encode() + b"\n"
            )
            self.process.stdin.flush()
        except OSError:
            raise Failure("the tool closed its input") from None

    def receive(self, deadline, seconds, leaving=False):
        """The tool's next message, before `deadline`, which is `seconds` long.

        With `leaving`, the tool has exited and this reads what it wrote on
        the way out: None at the end of that, or when the time is up.
        """
        while True:
            try:
                line = self.lines.get(timeout=max(0.0, deadline - time.monotonic()))
            except queue.Empty:
                if leaving:
                    # A program the tool started may hold its output open.
                    return None
                raise Failure(f"no answer within {seconds} seconds") from None
            if not line:
                if leaving:
                    return None
                raise Failure("the tool exited")
            if not line.endswith(b"\n"):
                raise Failure("a line longer than 1 MB, or one cut short")
            if not line.strip():
                continue
            try:
                return json.loads(line)
            except ValueError:
                raise Failure(f"a line that is not JSON: {line[:80]!r}") from None

    def close(self):
        """Ends the tool if it is still running, and leaves nothing behind."""
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait()
        try:
            self.process.stdin.close()
        except OSError:
            pass
        # The reader stops at the end of the tool's output. It is not waited
        # for longer than this: a program the tool started may hold the pipe.
        self.reader.join(timeout=EXIT_SECONDS)
        if not self.reader.is_alive():
            self.process.stdout.close()


class Run:
    """One tool put through the checks."""

    def __init__(self, link, manifest, data_folder):
        self.link = link
        self.data_folder = data_folder
        self.uses = set(manifest.get("uses", []))
        self.commands = [
            c["id"] for c in manifest.get("contributes", {}).get("commands", [])
        ]
        self.protocol = manifest.get("protocol")
        self.panels = manifest.get("contributes", {}).get("panels", [])
        # The pages the tool sent unprompted, by panel.
        self.rendered = {}
        self.values = {p["id"]: p["default"] for p in manifest.get("preferences", [])}
        self.next_id = 0
        self.refused = 0

    def request(self, method, params):
        self.next_id += 1
        self.link.send(
            {"jsonrpc": "2.0", "id": self.next_id, "method": method, "params": params}
        )
        return self.next_id

    def fail(self, request, code, message, data=None):
        error = {"code": code, "message": message}
        if data is not None:
            error["data"] = data
        self.link.send({"jsonrpc": "2.0", "id": request["id"], "error": error})

    def serve(self, request, refuse_all):
        """Answers one request from the tool as the app would."""
        method, params = request["method"], request.get("params", {})
        if method not in SERVICES:
            return self.fail(request, METHOD_NOT_FOUND, "method not found")
        service, result = SERVICES[method]
        if service not in self.uses:
            self.refused += 1
            return self.fail(
                request, NOT_IN_USES, "not listed in uses", {"service": service}
            )
        if refuse_all:
            self.refused += 1
            return self.fail(request, UNAVAILABLE, "not available right now")
        if service == "storage":
            if params.get("key") not in self.values:
                return self.fail(
                    request, INVALID_PARAMS, "not a preference the manifest declares"
                )
            if method == "storage/set":
                self.values[params["key"]] = params.get("value")
            else:
                result = {"value": self.values[params["key"]]}
        return self.link.send({"jsonrpc": "2.0", "id": request["id"], "result": result})

    def answer(self, request_id, seconds, refuse_all=False):
        """Plays the app until the tool answers request `request_id`."""
        deadline = time.monotonic() + seconds
        while True:
            message = self.link.receive(deadline, seconds)
            kind = kind_of(message)
            if kind in ("request", "notice"):
                check_params(message)
            if kind == "notice" and message["method"] == "ui/render":
                self.render(message["params"])
            if kind == "request":
                self.serve(message, refuse_all)
            elif kind in ("result", "failure"):
                if message.get("id") != request_id:
                    raise Failure(
                        f"an answer to a request that was not waiting: {message!r}"
                    )
                return kind, message

    def render(self, params):
        """A page the tool sent unprompted: for a panel its manifest declares."""
        if params["panel"] not in {panel.get("id") for panel in self.panels}:
            raise Failure(
                f"ui/render for a panel the manifest does not declare: {params['panel']}"
            )
        self.rendered[params["panel"]] = params["tree"]

    def handshake(self):
        params = {
            "protocolVersions": VERSIONS,
            "language": "en-US",
            "dataFolder": self.data_folder,
        }
        sent = self.request("initialize", params)
        message = self.link.receive(
            time.monotonic() + FIRST_ANSWER_SECONDS, FIRST_ANSWER_SECONDS
        )
        if kind_of(message) != "result" or message.get("id") != sent:
            raise Failure(
                f"something other than the answer to initialize came first: {message!r}"
            )
        result = message["result"]
        if (
            not isinstance(result, dict)
            or result.get("protocolVersion") not in VERSIONS
        ):
            raise Failure(f"the tool picked a version that was not offered: {result!r}")
        if not isinstance(result.get("toolVersion"), str):
            raise Failure(f"the tool did not say its own version: {result!r}")
        return f"version {result['protocolVersion']}, tool {result['toolVersion']}"

    def a_command(self):
        if not self.commands:
            return "the manifest declares no command"
        kind, message = self.answer(
            self.request("command/run", {"command": self.commands[0]}), ANSWER_SECONDS
        )
        if kind == "result" and not isinstance(message["result"], dict):
            raise Failure(f"a result that is not an object: {message!r}")
        return f"{self.commands[0]}: " + (
            "ran" if kind == "result" else f"refused, {message['error']['message']}"
        )

    def unknown(self):
        sent = self.request("command/run", {"command": "conformance.no-such-command"})
        kind, message = self.answer(sent, ANSWER_SECONDS)
        if kind != "failure":
            raise Failure(
                f"a command the tool does not have was answered as done: {message!r}"
            )
        return f"failure {message['error']['code']}"

    def a_panel(self):
        drawn = [
            panel for panel in self.panels if panel.get("kind", "blocks") == "blocks"
        ]
        if self.protocol != "2" or not drawn:
            return "the manifest declares no panel the app draws"
        panel = drawn[0]["id"]
        kind, message = self.answer(
            self.request("ui/open", {"panel": panel}), ANSWER_SECONDS
        )
        if kind != "result" or not isinstance(message["result"], dict):
            raise Failure(f"ui/open was not answered with a result: {message!r}")
        first = message["result"].get("tree", self.rendered.get(panel))
        if first is None or not is_tree(first):
            raise Failure(f"ui/open was not answered with a page: {message!r}")
        buttons = [
            block["id"]
            for block in first["blocks"]
            if isinstance(block, dict) and block.get("type") == "button"
        ]
        said = f"{panel}: a page of {len(first['blocks'])} blocks"
        if buttons:
            sent = self.request(
                "ui/event", {"panel": panel, "block": buttons[0], "event": "tap"}
            )
            kind, message = self.answer(sent, ANSWER_SECONDS)
            if kind != "result" or not isinstance(message["result"], dict):
                raise Failure(f"a tap was not answered with a result: {message!r}")
            result = message["result"]
            nxt = result.get("tree", self.rendered.get(panel))
            if "tree" in result and not is_tree(result["tree"]):
                raise Failure(
                    f"a tap was answered with something that is not a page: {result!r}"
                )
            if result.get("keep") is not True and (nxt is None or nxt == first):
                raise Failure(f"a tap on {buttons[0]} was answered with the same page")
            said += f", and a new page after a tap on {buttons[0]}"
        self.link.send(
            {"jsonrpc": "2.0", "method": "ui/close", "params": {"panel": panel}}
        )
        return said

    def refusals(self):
        if not self.commands:
            return "the manifest declares no command"
        before = self.refused
        sent = self.request("command/run", {"command": self.commands[0]})
        self.answer(sent, ANSWER_SECONDS, refuse_all=True)
        count = self.refused - before
        return (
            f"{count} refused"
            if count
            else "the tool asked the app for nothing, so nothing was refused"
        )

    def shutdown(self):
        self.link.send({"jsonrpc": "2.0", "method": "shutdown"})
        self.link.process.stdin.close()
        try:
            status = self.link.process.wait(timeout=EXIT_SECONDS)
        except subprocess.TimeoutExpired:
            raise Failure(
                f"still running {EXIT_SECONDS} seconds after shutdown"
            ) from None
        if status != 0:
            raise Failure(f"exited with {status}")
        more = self.last_words()
        if more:
            return f"exited with 0, after {more} more message" + (
                "s" if more > 1 else ""
            )
        return "exited with 0"

    def last_words(self):
        """Reads what the tool wrote after its last answer, to the end.

        The app reads these lines too, so each must be a message that carries
        its own params. Nothing is waiting for an answer by now, so an answer
        is a mistake. A request is not answered: the link is closing.
        """
        count = 0
        deadline = time.monotonic() + EXIT_SECONDS
        while True:
            # A line that is already waiting is handed over whatever the time,
            # so the time is asked here: a program the tool left behind that
            # writes without end must not hold this past its limit.
            if time.monotonic() >= deadline:
                raise Failure(f"still writing {EXIT_SECONDS} seconds after it exited")
            message = self.link.receive(deadline, EXIT_SECONDS, leaving=True)
            if message is None:
                return count
            count += 1
            if kind_of(message) in ("result", "failure"):
                raise Failure(
                    f"an answer to a request that was not waiting: {message!r}"
                )
            check_params(message)


def main(arguments=None):
    parser = argparse.ArgumentParser(
        description="Check a tool against the Vitruvian tool protocol, versions 1 and 2."
    )
    parser.add_argument(
        "folder", help="the tool's folder, which holds vitruvian-tool.json"
    )
    parser.add_argument("--via", help="start the tool's program through this program")
    parser.add_argument(
        "--expect-refusal",
        action="store_true",
        help="fail unless the refusals check refused something",
    )
    options = parser.parse_args(arguments)
    # `bazel run` starts a program in its own folder; this is where the person was.
    folder = os.path.abspath(
        os.path.join(os.environ.get("BUILD_WORKING_DIRECTORY", ""), options.folder)
    )
    with open(os.path.join(folder, "vitruvian-tool.json"), encoding="utf-8") as handle:
        manifest = json.load(handle)
    program = os.path.join(folder, manifest["runtime"]["exec"])
    command = [options.via, program] if options.via else [program]

    passed = True
    with tempfile.TemporaryDirectory(prefix="vitruvian-conformance-") as data_folder:
        # Whatever happens from here on, the tool is ended and waited for.
        link = Link(command, data_folder)
        try:
            run = Run(link, manifest, data_folder)
            checks = [
                ("handshake", run.handshake),
                ("a command", run.a_command),
                ("unknown", run.unknown),
                ("a panel", run.a_panel),
                ("refusals", run.refusals),
                ("shutdown", run.shutdown),
            ]
            for name, check in checks:
                if not passed:
                    print(f"skipped  {name}")
                    continue
                try:
                    print(f"ok       {name}: {check()}")
                except Failure as failure:
                    passed = False
                    print(f"NOT OK   {name}: {failure}")
            if passed and options.expect_refusal and run.refused == 0:
                passed = False
                print(
                    "NOT OK   refusals: nothing was refused, and --expect-refusal was given"
                )
        finally:
            link.close()
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
