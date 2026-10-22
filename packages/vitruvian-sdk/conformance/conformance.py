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

Seven things are checked, in order, and the first failure stops the run:

  handshake   the tool answers `initialize` first, with a version offered
  a command   its first command is run and answered
  unknown     a command it does not have is answered with a failure
  a panel     for a tool of protocol 2: its first panel the app draws is
              opened and answered with a page; its first button is tapped and
              answered with a new page; the panel is closed. Then each other
              panel the app draws is opened, answered with a page, and closed
  refusals    the command is run again with every request the tool makes
              refused, and is still answered
  shutdown    after `shutdown` and the end of its input, the tool exits with 0,
              and what it wrote on the way out is messages too
  an older app  the tool is started once more, by an app from before 3.48: its
              hello names no `features`, and a `ui/status` is answered with
              -32601. The tool must still answer the hello, run its command,
              draw its panels and leave on `shutdown`, and no page of any of
              its panels may hold chips, a heading with `section: true` or
              `help`, which that app does not draw. Nor may it send
              `notify/notice` or `ui/dock`, which that app does not know

Every line the tool writes must be one JSON-RPC 2.0 message, at most 1 MB,
and a message the protocol has must carry the params the protocol gives it.
A page sent with `ui/render` must be for a panel the manifest declares, and a
`ui/status` must come from a tool whose manifest declares a status, and a
`ui/dock` from one that declares a slot. A tool that declares a slot is told
where it is, with `ui/slot`, after the hello. A `notify/notice` or a
`ui/dock` must go only to an app whose hello names `notify.notice` or
`ui.slot`. On every
page, each block's id and each list row's id must be a name, as the app reads
it: ASCII letters, digits, `.`, `-` and `_`, at most 128 of them, with no dot
at either end and no two together. The app refuses the whole page otherwise.
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
NEEDS_ID = ("button", "toggle", "field", "list", "choice", "chips")
VERSIONS = ["1", "2"]
# What this app says it has beyond the first release of the protocol version,
# in the hello. An app before 3.48 says nothing.
FEATURES = [
    "ui.status",
    "ui.choice",
    "preferences.options",
    "ui.status.activity",
    "ui.open.settings",
    "ui.chips",
    "ui.sections",
    "notify.notice",
    "ui.slot",
    "preferences.folder",
]
STATES = ("none", "ok", "busy", "attention", "failure")
MAX_CHOICE_OPTIONS = 64
MAX_CHOICE_VALUE = 128
# The longest a name may be: a block's id, a list row's id. The app's rule is
# `ManifestRules.isWellFormedName`, with `ManifestLimits.maxNameLength`.
MAX_NAME = 128
NAME_CHARACTERS = frozenset(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"
)
# The most `ui/status` a tool may send an app that answers each with -32601.
# One learns that the app has none; a handful is patience; more is a tool
# that does not read the answer.
MAX_STATUS_AFTER_REFUSAL = 5

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
    "notify/notice": ("notify", {}),
}

# The requests an app has only when its hello names the feature: an app that
# does not answers them with -32601, and a tool must ask before it sends one.
GATED = {
    "notify/notice": ("notify.notice", "send notify/hud there"),
    "ui/dock": ("ui.slot", "dock nothing there"),
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


def is_ui_text(value):
    """Text the person reads: a string, or one entry per language with
    English under en."""
    if is_text(value):
        return True
    return (
        isinstance(value, dict)
        and is_text(value.get("en"))
        and all(map(is_text, value.values()))
    )


def is_state(value):
    return value in STATES


def is_since(value):
    """A start time: Unix seconds, never before 1970."""
    return is_number(value) and value >= 0


def is_choice(value):
    """A choice's own fields: what is selected, and from 1 to 64 options,
    each a value and a title, no two with one value."""
    options = value.get("options")
    if not is_text(value.get("value")) or len(value["value"]) > MAX_CHOICE_VALUE:
        return False
    if not isinstance(options, list) or not 1 <= len(options) <= MAX_CHOICE_OPTIONS:
        return False
    for option in options:
        if not isinstance(option, dict) or not is_ui_text(option.get("title")):
            return False
        if not is_text(option.get("value")) or len(option["value"]) > MAX_CHOICE_VALUE:
            return False
    if len({option["value"] for option in options}) != len(options):
        return False
    return ("title" not in value or is_ui_text(value["title"])) and (
        "enabled" not in value or is_flag(value["enabled"])
    )


def is_chips(value):
    """Chips' own fields: from 1 to 64 options, each a value, a title and
    whether it is on, no two with one value; a chip that cannot be turned may
    say why."""
    options = value.get("options")
    if not isinstance(options, list) or not 1 <= len(options) <= MAX_CHOICE_OPTIONS:
        return False
    for option in options:
        if not isinstance(option, dict) or not is_ui_text(option.get("title")):
            return False
        if not is_text(option.get("value")) or len(option["value"]) > MAX_CHOICE_VALUE:
            return False
        if not is_flag(option.get("on")):
            return False
        if "enabled" in option and not is_flag(option["enabled"]):
            return False
        if "reason" in option and not is_ui_text(option["reason"]):
            return False
    if len({option["value"] for option in options}) != len(options):
        return False
    return ("title" not in value or is_ui_text(value["title"])) and (
        "enabled" not in value or is_flag(value["enabled"])
    )


# The kinds that may carry help: a line or two under the control.
HAS_HELP = ("toggle", "field", "choice", "chips")


def is_block(value):
    """A block: a kind, and an id where its kind needs one, which is text
    on any block that has one. A choice and chips are held to their own
    rules, a heading's section is yes or no, and help is text. A kind this
    script does not know is a later version's, and is fine. Whether each id
    is a name is `misnamed`'s, which says which."""
    if not isinstance(value, dict) or not is_text(value.get("type")):
        return False
    kind = value["type"]
    return (
        (kind not in NEEDS_ID or is_text(value.get("id")))
        and (value.get("id") is None or is_text(value["id"]))
        and (kind != "choice" or is_choice(value))
        and (kind != "chips" or is_chips(value))
        and (kind != "heading" or "section" not in value or is_flag(value["section"]))
        and (kind not in HAS_HELP or "help" not in value or is_ui_text(value["help"]))
    )


def name_rule_broken(text):
    """The rule of a name that `text` breaks, in words, or None when it is
    a name: ASCII letters, digits, `.`, `-` and `_`, at most 128 of them,
    with no dot at either end and no two together."""
    if not text:
        return "at least one character"
    if not set(text) <= NAME_CHARACTERS:
        return "ASCII letters, digits, '.', '-' and '_' only"
    if len(text) > MAX_NAME:
        return f"at most {MAX_NAME} characters"
    if text.startswith(".") or text.endswith("."):
        return "no '.' at either end"
    if ".." in text:
        return "no two '.' together"
    return None


def misnamed(tree, panel):
    """What on a page of `panel` has an id that is not a name, said in
    words, or None. The app reads every block's id, of any kind, and every
    row's of a list, as a name, and refuses the whole page for one that is
    not: the panel keeps the page it had."""
    refused = "Vitruvian refuses the whole page"
    for block in tree["blocks"]:
        named = block.get("id")
        if named is not None:
            rule = name_rule_broken(named)
            if rule:
                return (
                    f"the page of {panel} has block id {named!r}, which is not a "
                    f"valid name ({rule}): {refused}"
                )
        rows = block.get("rows") if block["type"] == "list" else None
        for row in rows if isinstance(rows, list) else []:
            if not isinstance(row, dict):
                continue
            if not is_text(row.get("id")):
                return (
                    f"the page of {panel} has a row in list {named!r} whose id is "
                    f"missing or not text: {refused}"
                )
            rule = name_rule_broken(row["id"])
            if rule:
                return (
                    f"the page of {panel} has list row id {row['id']!r} in list "
                    f"{named!r}, which is not a valid name ({rule}): {refused}"
                )
    return None


def newer_than(tree, features, panel):
    """What a page of `panel` holds that an app with only these features
    does not draw, said in words, or None. `features` is None for an app
    that named none."""
    have = features or []
    for block in tree["blocks"]:
        kind = block["type"]
        if kind == "chips" and "ui.chips" not in have:
            return (
                f"the page of {panel} holds chips, which an app without ui.chips "
                "draws as their fallback text and nobody can change: ask supports "
                "first, and send a toggle for each option"
            )
        if "ui.sections" in have:
            continue
        # `section: false` is a plain heading, which every app draws.
        if kind == "heading" and block.get("section") is True:
            return (
                f"the page of {panel} holds a heading that starts a section, which "
                "an app without ui.sections draws as a plain heading: ask supports "
                "first"
            )
        if kind in HAS_HELP and "help" in block:
            return (
                f"the page of {panel} holds help on a {kind}, which an app without "
                "ui.sections leaves out: ask supports first, and send a text after "
                "the control"
            )
    return None


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
    "ui/status": {"state": is_state},
    "notify/notice": {"icon": is_text, "title": is_text},
    "ui/dock": {},
}

# The params a message may carry, and must carry rightly when it does.
OPTIONAL_PARAMS = {
    "notify/notice": {"detail": is_text, "system": is_flag},
    "ui/badge": {"count": is_count, "dot": is_flag},
    "ui/status": {
        "text": is_ui_text,
        "icon": is_text,
        "activity": is_ui_text,
        "since": is_since,
    },
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

    def __init__(self, link, manifest, data_folder, features=FEATURES):
        """`features` is what the app says it has, in the hello. None is an
        app from before 3.48: it says nothing, and answers `ui/status` with
        -32601."""
        self.link = link
        self.data_folder = data_folder
        self.features = features
        self.shows_status = "status" in manifest.get("contributes", {})
        # Whether that status may carry a few words: `"activity": true`.
        self.shows_activity = (
            manifest.get("contributes", {}).get("status", {}).get("activity") is True
        )
        # Whether the manifest declares a slot, and how often the tool asked
        # the app to show it.
        self.has_slot = "slot" in manifest.get("contributes", {})
        self.docked = 0
        # Each status the tool set, in order, and how many an older app
        # refused.
        self.statuses = []
        self.status_refused = 0
        # Whether the first page of the panel held a choice.
        self.drew_choice = False
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
        if method == "ui/status":
            return self.status(request, refuse_all)
        if method in GATED:
            feature, instead = GATED[method]
            if feature not in (self.features or []):
                self.fail(request, METHOD_NOT_FOUND, "method not found")
                raise Failure(
                    f"{method} to an app whose hello does not name {feature}. That app "
                    f"answers it with -32601: ask what the app has first, and {instead}"
                )
        if method == "ui/dock":
            return self.dock(request, refuse_all)
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

    def status(self, request, refuse_all):
        """Answers `ui/status` as the app would. It needs nothing in `uses`:
        the manifest's declaration is the permission."""
        if self.features is None:
            # An app before 3.48 does not know the method.
            self.status_refused += 1
            self.fail(request, METHOD_NOT_FOUND, "unknown method")
            if self.status_refused > MAX_STATUS_AFTER_REFUSAL:
                raise Failure(
                    "the tool went on sending ui/status to an app that answered it with "
                    f"-32601: {self.status_refused} times. Ask what the app has first, "
                    "or stop at the first refusal"
                )
            return None
        if not self.shows_status:
            self.fail(request, INVALID_PARAMS, "the manifest declares no status")
            raise Failure(
                "ui/status from a tool whose manifest declares no status. The app "
                "answers it with -32602: add `contributes.status`"
            )
        if refuse_all:
            self.refused += 1
            return self.fail(request, UNAVAILABLE, "not available right now")
        self.statuses.append(request["params"]["state"])
        self.link.send({"jsonrpc": "2.0", "id": request["id"], "result": {}})
        words = any(name in request["params"] for name in ("activity", "since"))
        if words and not self.shows_activity:
            # The app answers it with {} and draws the mark: the words are
            # what is lost, so it is the author's to fix.
            raise Failure(
                "ui/status with words from a tool whose manifest does not declare them. "
                "The app draws the mark and leaves the words out: add "
                '"activity": true to contributes.status'
            )
        return None

    def dock(self, request, refuse_all):
        """Answers `ui/dock` as the app would. It needs nothing in `uses`:
        the manifest's slot is the permission."""
        if not self.has_slot:
            self.fail(request, INVALID_PARAMS, "the manifest declares no slot")
            raise Failure(
                "ui/dock from a tool whose manifest declares no slot. The app "
                "answers it with -32602: add `contributes.slot`"
            )
        if refuse_all:
            self.refused += 1
            return self.fail(request, UNAVAILABLE, "not available right now")
        self.docked += 1
        return self.link.send({"jsonrpc": "2.0", "id": request["id"], "result": {}})

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
        wrong = misnamed(params["tree"], params["panel"])
        if wrong:
            raise Failure(wrong)
        self.rendered[params["panel"]] = params["tree"]

    def hello(self):
        """What `initialize` carries. An app before 3.48 has no `features`."""
        params = {
            "protocolVersions": VERSIONS,
            "language": "en-US",
            "dataFolder": self.data_folder,
        }
        if self.features is not None:
            params["features"] = list(self.features)
        return params

    def handshake(self):
        sent = self.request("initialize", self.hello())
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
        said = f"version {result['protocolVersion']}, tool {result['toolVersion']}"
        if self.has_slot and "ui.slot" in (self.features or []):
            # Where its slot is, as the app says when the island opens on it.
            self.link.send(
                {
                    "jsonrpc": "2.0",
                    "method": "ui/slot",
                    "params": {
                        "visible": True,
                        "x": 0,
                        "y": 0,
                        "width": 400,
                        "height": 300,
                    },
                }
            )
            said += ", and told where its slot is"
        return said

    def a_command(self):
        if not self.commands:
            return "the manifest declares no command"
        before, docked = len(self.statuses), self.docked
        kind, message = self.answer(
            self.request("command/run", {"command": self.commands[0]}), ANSWER_SECONDS
        )
        if kind == "result" and not isinstance(message["result"], dict):
            raise Failure(f"a result that is not an object: {message!r}")
        said = f"{self.commands[0]}: " + (
            "ran" if kind == "result" else f"refused, {message['error']['message']}"
        )
        if len(self.statuses) > before:
            said += ", and set the status: " + ", ".join(self.statuses[before:])
        if self.docked > docked:
            said += ", and asked for its slot"
        return said

    def unknown(self):
        sent = self.request("command/run", {"command": "conformance.no-such-command"})
        kind, message = self.answer(sent, ANSWER_SECONDS)
        if kind != "failure":
            raise Failure(
                f"a command the tool does not have was answered as done: {message!r}"
            )
        return f"failure {message['error']['code']}"

    def drawn(self):
        """The ids of the panels the app draws from blocks, in the
        manifest's order."""
        if self.protocol != "2":
            return []
        return [
            panel["id"]
            for panel in self.panels
            if panel.get("kind", "blocks") == "blocks"
        ]

    def opened_page(self, panel):
        """Opens `panel` and reads the page it is answered with: one this
        app draws, holding nothing it does not have."""
        kind, message = self.answer(
            self.request("ui/open", {"panel": panel}), ANSWER_SECONDS
        )
        if kind != "result" or not isinstance(message["result"], dict):
            raise Failure(f"ui/open was not answered with a result: {message!r}")
        page = message["result"].get("tree", self.rendered.get(panel))
        if page is None or not is_tree(page):
            raise Failure(f"ui/open was not answered with a page: {message!r}")
        wrong = misnamed(page, panel)
        if wrong:
            raise Failure(wrong)
        self.drew_choice = self.drew_choice or any(
            block.get("type") == "choice" for block in page["blocks"]
        )
        newer = newer_than(page, self.features, panel)
        if newer:
            raise Failure(newer)
        return page

    def a_panel(self):
        """The first panel the app draws is opened, its first button tapped,
        and it is closed; then each other panel it draws is opened and
        closed, so every page a person can open is checked."""
        drawn = self.drawn()
        if not drawn:
            return "the manifest declares no panel the app draws"
        said = self.first_panel(drawn[0])
        for panel in drawn[1:]:
            page = self.opened_page(panel)
            said += f"; {panel}: a page of {len(page['blocks'])} blocks"
            self.link.send(
                {"jsonrpc": "2.0", "method": "ui/close", "params": {"panel": panel}}
            )
        return said

    def first_panel(self, panel):
        """The first panel the app draws: opened, its first button tapped,
        and closed."""
        first = self.opened_page(panel)
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
            wrong = misnamed(result["tree"], panel) if "tree" in result else None
            if wrong:
                raise Failure(wrong)
            newer = newer_than(nxt, self.features, panel) if nxt is not None else None
            if newer:
                raise Failure(newer)
            opened = self.opened(result)
            if opened:
                said += f", and {opened} after a tap on {buttons[0]}"
            elif result.get("keep") is not True and (nxt is None or nxt == first):
                raise Failure(f"a tap on {buttons[0]} was answered with the same page")
            else:
                said += f", and a new page after a tap on {buttons[0]}"
        self.link.send(
            {"jsonrpc": "2.0", "method": "ui/close", "params": {"panel": panel}}
        )
        return said

    def opened(self, result):
        """What a tap's answer opens with `open`: one of the tool's window
        panels, or its settings panel on an app that names ui.open.settings.
        None when it opens nothing. An id the manifest does not declare, or
        one the app would not open, fails the run: the app would open
        nothing and only the tool's log would say so."""
        if "open" not in result:
            return None
        name = result["open"]
        if not is_text(name):
            raise Failure(f"a tap's open is not a panel's id: {result!r}")
        placement = next(
            (p.get("placement") for p in self.panels if p.get("id") == name), None
        )
        if placement is None:
            raise Failure(
                f"a tap's open names {name}, a panel the manifest does not declare"
            )
        if placement == "window":
            return f"the window {name}"
        if placement == "settings":
            if "ui.open.settings" not in (self.features or []):
                raise Failure(
                    f"a tap's open names the settings panel {name}, which an app "
                    "without ui.open.settings does not open: ask supports first"
                )
            return f"the settings panel {name}"
        raise Failure(
            f"a tap's open names {name}, a panel of the {placement}, which the app "
            "does not open: only a window or the tool's settings panel opens"
        )

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


def an_older_app(command, manifest):
    """The tool, started once more by an app from before 3.48: its hello
    names no `features`, and it answers `ui/status` with -32601. The tool
    must do everything it did, less the status. A tool that needs what the
    app lacks degrades; it does not stop."""
    with tempfile.TemporaryDirectory(prefix="vitruvian-conformance-") as data_folder:
        link = Link(command, data_folder)
        try:
            run = Run(link, manifest, data_folder, features=None)
            try:
                run.handshake()
                did = ["answered the hello"]
                if run.commands:
                    run.a_command()
                    did.append(f"ran {run.commands[0]}")
                if not run.a_panel().startswith("the manifest declares no panel"):
                    did += [f"drew {panel}" for panel in run.drawn()]
                run.shutdown()
            except Failure as failure:
                if run.status_refused == 0 or str(failure).startswith(
                    ("the tool went on", "the page of")
                ):
                    raise
                raise Failure(
                    "the tool did not carry on after an app that has no ui/status refused "
                    f"it with -32601 ({failure}). Ask what the app has first, or treat "
                    "the refusal as no status"
                ) from None
        finally:
            link.close()
    said = ", ".join(did) + " and left with 0; "
    if run.status_refused:
        said += (
            f"{run.status_refused} ui/status refused with -32601, as an app before "
            "3.48 does"
        )
    else:
        said += "it sent no ui/status"
    if run.drew_choice:
        said += (
            "; its page holds a choice, which that app draws as its fallback text "
            "and nobody can change: send a field to an app without ui.choice"
        )
    return said


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
                ("an older app", lambda: an_older_app(command, manifest)),
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
