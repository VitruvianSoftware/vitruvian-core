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
"""The conformance script, proven two ways: the reference tool passes it, and
a tool that breaks the protocol fails the check meant to catch it."""

import contextlib
import io
import json
import os
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import conformance

REFERENCE = os.path.join(HERE, "reference-tool")

# A tool that goes wrong in the way BROKEN_HOW names, and is otherwise the
# reference tool without its request to the app.
BROKEN_TOOL = """
import json, os, sys, time
how = os.environ["BROKEN_HOW"]
def send(message):
    sys.stdout.write(json.dumps(message) + "\\n")
    sys.stdout.flush()
for line in sys.stdin:
    message = json.loads(line)
    method = message.get("method")
    if method == "initialize":
        if how == "speaks first":
            send({"jsonrpc": "2.0", "method": "log", "params": {"message": "starting"}})
        if how == "not json":
            sys.stdout.write("starting up\\n")
        version = "2" if how == "wrong version" else "1"
        send({"jsonrpc": "2.0", "id": message["id"], "result": {"protocolVersion": version, "toolVersion": "0"}})
        if how == "states badly":
            send({"jsonrpc": "2.0", "method": "commands/state", "params": {"runnable": "hello"}})
    elif method == "command/run":
        if how == "never answers":
            continue
        known = message["params"]["command"] == "hello"
        if how == "asks badly":
            send({"jsonrpc": "2.0", "id": "a", "method": "notify/hud", "params": {"icon": "hand.wave", "message": 5}})
        if how == "answers another":
            send({"jsonrpc": "2.0", "id": message["id"] + 100, "result": {}})
            continue
        if known or how == "runs anything":
            send({"jsonrpc": "2.0", "id": message["id"], "result": {}})
        else:
            send({"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32602, "message": "no such command"}})
    elif method == "shutdown" and how == "exits with 3":
        sys.exit(3)
if how == "will not exit":
    time.sleep(30)
"""

# The longest the script may spend on one broken tool. Its own deadlines are
# 2 seconds; the rest is room for a busy machine to start a process.
SLOWEST_SECONDS = 15

# How a tool goes wrong, and the one line the script must print for it: the
# check that caught it, and why.
BROKEN = {
    "speaks first": "NOT OK   handshake: something other than the answer to initialize came first",
    "not json": "NOT OK   handshake: a line that is not JSON",
    "wrong version": "NOT OK   handshake: the tool did not pick version 1",
    "never answers": "NOT OK   a command: no answer within 2 seconds",
    "answers another": "NOT OK   a command: an answer to a request that was not waiting",
    "asks badly": "NOT OK   a command: notify/hud with params that are not its own",
    "states badly": "NOT OK   a command: commands/state with params that are not its own",
    "runs anything": "NOT OK   unknown: a command the tool does not have was answered as done",
    "exits with 3": "NOT OK   shutdown: exited with 3",
    "will not exit": "NOT OK   shutdown: still running 2 seconds after shutdown",
}


def check(folder, *options):
    """What the script printed for the tool in `folder`, and its exit status."""
    printed = io.StringIO()
    with contextlib.redirect_stdout(printed):
        status = conformance.main([folder, "--via", sys.executable, *options])
    return status, printed.getvalue()


def main():
    problems = []

    status, printed = check(REFERENCE, "--expect-refusal")
    wanted = [
        "ok       handshake",
        "ok       a command: hello: ran",
        "ok       unknown",
        "1 refused",
        "exited with 0",
    ]
    if status != 0 or not all(piece in printed for piece in wanted):
        problems.append(f"the reference tool does not pass:\n{printed}")

    with open(
        os.path.join(REFERENCE, "vitruvian-tool.json"), encoding="utf-8"
    ) as handle:
        manifest = json.load(handle)
    manifest["runtime"]["exec"] = "broken.py"
    with tempfile.TemporaryDirectory() as folder:
        with open(
            os.path.join(folder, "vitruvian-tool.json"), "w", encoding="utf-8"
        ) as handle:
            json.dump(manifest, handle)
        with open(os.path.join(folder, "broken.py"), "w", encoding="utf-8") as handle:
            handle.write(BROKEN_TOOL)
        for how, line in BROKEN.items():
            os.environ["BROKEN_HOW"] = how
            started = time.monotonic()
            status, printed = check(folder)
            took = time.monotonic() - started
            failed = [
                text for text in printed.splitlines() if text.startswith("NOT OK")
            ]
            if status != 1 or len(failed) != 1 or not failed[0].startswith(line):
                problems.append(f"a tool that {how} is not caught:\n{printed}")
            # A tool that says nothing, or will not go, costs one deadline
            # and never the whole test.
            if took > SLOWEST_SECONDS:
                problems.append(f"a tool that {how} held the script {took:.1f} seconds")
        os.environ["BROKEN_HOW"] = "nothing"
        status, printed = check(folder, "--expect-refusal")
        if status != 1 or "--expect-refusal was given" not in printed:
            problems.append(
                f"a tool that asks for nothing passes --expect-refusal:\n{printed}"
            )
        status, printed = check(folder)
        if status != 0 or "nothing was refused" not in printed:
            problems.append(f"a tool that only answers does not pass:\n{printed}")

    for problem in problems:
        print(problem, file=sys.stderr)
    print("conformance: " + ("FAILED" if problems else "OK"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
