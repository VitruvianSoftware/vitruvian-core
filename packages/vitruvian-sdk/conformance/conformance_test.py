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
import signal
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
LEFT_BEHIND = os.environ.get("BROKEN_LEFT_BEHIND", "")
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
    elif method == "shutdown" and how == "parts badly":
        send({"jsonrpc": "2.0", "method": "commands/state", "params": {"runnable": "hello"}})
        sys.exit(0)
    elif method == "shutdown" and how == "parts well":
        send({"jsonrpc": "2.0", "method": "log", "params": {"message": "going"}})
        sys.exit(0)
    elif method == "shutdown" and how == "parts mid-line":
        sys.stdout.write('{"jsonrpc": "2.0", "method": "log"')
        sys.stdout.flush()
        sys.exit(0)
    elif method == "shutdown" and how == "never stops writing":
        # A program the tool leaves behind, which holds its output and writes
        # good messages as fast as it can. It ends by itself after a while,
        # and the test ends it sooner.
        import subprocess
        left = subprocess.Popen([sys.executable, "-c", LEFT_BEHIND], stdin=subprocess.DEVNULL)
        with open(os.environ["BROKEN_PIDFILE"], "w") as handle:
            handle.write(str(left.pid))
        sys.exit(0)
if how == "will not exit":
    time.sleep(30)
"""

# What a tool that never stops writing leaves behind. It writes for longer
# than the script reads a tool's last words, and no longer.
LEFT_BEHIND = """
import os, time
line = b'{"jsonrpc": "2.0", "method": "log", "params": {"message": "still here"}}\\n'
end = time.monotonic() + 2.5
try:
    while time.monotonic() < end:
        os.write(1, line)
except OSError:
    pass
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
    "parts badly": "NOT OK   shutdown: commands/state with params that are not its own",
    "parts mid-line": "NOT OK   shutdown: a line longer than 1 MB, or one cut short",
}


def check(folder, *options):
    """What the script printed for the tool in `folder`, and its exit status."""
    printed = io.StringIO()
    with contextlib.redirect_stdout(printed):
        status = conformance.main([folder, "--via", sys.executable, *options])
    return status, printed.getvalue()


def end_left_behind(pid_file):
    """Ends the program a broken tool left behind, if it left one."""
    if not os.path.exists(pid_file):
        return
    with open(pid_file, encoding="utf-8") as handle:
        pid = int(handle.read())
    os.remove(pid_file)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


class AlwaysWaiting:
    """A link with a good line always waiting, as a program that writes faster
    than the script reads leaves it. It gives up a while after the script
    should have, so that a script that reads on cannot hold the test."""

    def __init__(self):
        self.give_up = time.monotonic() + 2 * conformance.EXIT_SECONDS

    def receive(self, deadline, seconds, leaving=False):
        if time.monotonic() >= self.give_up:
            raise conformance.Failure("read on past its limit")
        return {"jsonrpc": "2.0", "method": "log", "params": {"message": "still here"}}


def a_line_always_waiting():
    """The script's last read ends at its limit even when a line is always
    waiting, and says why. This is the rule itself, with no process and so no
    race in it."""
    run = conformance.Run(AlwaysWaiting(), {}, "")
    started = time.monotonic()
    try:
        said = f"read {run.last_words()} messages and was content"
    except conformance.Failure as failure:
        said = str(failure)
    took = time.monotonic() - started
    wanted = f"still writing {conformance.EXIT_SECONDS} seconds after it exited"
    if said != wanted or took > conformance.EXIT_SECONDS + 1:
        return [f"a line always waiting: {said}, after {took:.1f} seconds"]
    return []


def never_stops_writing(folder):
    """A real tool that leaves a program behind, writing without end.

    The script ends within its bound and names the check. Which of two things
    it says is a matter of timing: `still writing` when a line was waiting as
    the time ran out, and a count when, at that instant, none was. Both end
    the read; `a_line_always_waiting` holds the rule without the timing.
    """
    pid_file = os.path.join(folder, "left-behind.pid")
    os.environ["BROKEN_HOW"] = "never stops writing"
    os.environ["BROKEN_PIDFILE"] = pid_file
    os.environ["BROKEN_LEFT_BEHIND"] = LEFT_BEHIND
    started = time.monotonic()
    try:
        status, printed = check(folder)
    finally:
        end_left_behind(pid_file)
    took = time.monotonic() - started
    last = printed.splitlines()[-1] if printed else ""
    caught = status == 1 and last == (
        f"NOT OK   shutdown: still writing {conformance.EXIT_SECONDS} seconds"
        " after it exited"
    )
    counted = status == 0 and last.startswith(
        "ok       shutdown: exited with 0, after "
    )
    problems = []
    if not (caught or counted):
        problems.append(f"a tool that never stops writing:\n{printed}")
    if took > SLOWEST_SECONDS:
        problems.append(
            f"a tool that never stops writing held the script {took:.1f} seconds"
        )
    return problems


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
        os.environ["BROKEN_HOW"] = "parts well"
        status, printed = check(folder)
        if status != 0 or "exited with 0, after 1 more message" not in printed:
            problems.append(
                f"a tool that says a last good word does not pass:\n{printed}"
            )
        problems += never_stops_writing(folder)
    problems += a_line_always_waiting()

    for problem in problems:
        print(problem, file=sys.stderr)
    print("conformance: " + ("FAILED" if problems else "OK"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
