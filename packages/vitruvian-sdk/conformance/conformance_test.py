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
"""The conformance script, proven two ways: the reference tools pass it, one
for each protocol version, and a tool that breaks the protocol fails the check
meant to catch it."""

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
# The reference tool of protocol 2: the first one, plus one panel.
REFERENCE_2 = os.path.join(HERE, "reference-tool-2")

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
        version = "3" if how == "wrong version" else "1"
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

# A tool of protocol 2 with one panel, which goes wrong in the way
# BROKEN_HOW names, or draws well when it is "draws well".
BROKEN_PANEL_TOOL = """
import json, os, sys
how = os.environ["BROKEN_HOW"]
count = 0
features = []
def send(message):
    sys.stdout.write(json.dumps(message) + "\\n")
    sys.stdout.flush()
def page():
    blocks = [{"type": "text", "text": "Pressed %d times" % count},
              {"type": "button", "id": "add", "title": "Add one"}]
    # A block, or a row of a list, named by BROKEN_ID, which may be no name.
    named = os.environ.get("BROKEN_ID")
    if how == "names a block":
        blocks.append({"type": "toggle", "id": named, "title": "Hook", "value": False})
    if how == "names a plain row":
        blocks.append({"type": "row", "id": named, "title": "web"})
    if how == "names a row of a list":
        blocks.append({"type": "list", "id": "hooks", "rows": [{"id": named, "title": "Claude Code"}]})
    if how == "leaves a row of a list unnamed":
        blocks.append({"type": "list", "id": "hooks", "rows": [{"title": "Claude Code"}]})
    return {"blocks": blocks}
for line in sys.stdin:
    message = json.loads(line)
    method = message.get("method")
    if method == "initialize":
        features = message["params"].get("features", [])
        send({"jsonrpc": "2.0", "id": message["id"], "result": {"protocolVersion": "2", "toolVersion": "0"}})
    elif method == "command/run":
        if message["params"]["command"] == "hello":
            send({"jsonrpc": "2.0", "id": message["id"], "result": {}})
        else:
            send({"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32602, "message": "no such command"}})
    elif method == "ui/open":
        if how == "puts a section in its settings" and message["params"]["panel"] == "settings":
            heading = {"type": "heading", "text": "Counting", "section": True}
            send({"jsonrpc": "2.0", "id": message["id"], "result": {"tree": {"blocks": [heading]}}})
            continue
        if how == "renders an unknown panel":
            send({"jsonrpc": "2.0", "method": "ui/render", "params": {"panel": "nowhere", "tree": page()}})
        if how == "opens with no page":
            send({"jsonrpc": "2.0", "id": message["id"], "result": {}})
        else:
            send({"jsonrpc": "2.0", "id": message["id"], "result": {"tree": page()}})
    elif method == "ui/event":
        opens = {"opens its settings": "settings", "opens its settings without asking": "settings",
                 "opens a window": "log", "opens an undeclared panel": "elsewhere",
                 "opens its island page": "counter"}.get(how)
        if how == "opens its settings" and "ui.open.settings" not in features:
            opens = None
        if opens:
            send({"jsonrpc": "2.0", "id": message["id"], "result": {"open": opens}})
            continue
        if how != "answers a tap with the same page":
            count += 1
        send({"jsonrpc": "2.0", "id": message["id"], "result": {"tree": page()}})
    elif method == "shutdown":
        sys.exit(0)
"""

# How a tool that draws goes wrong, and the line the script must print.
BROKEN_PANEL = {
    "renders an unknown panel": "NOT OK   a panel: ui/render for a panel the manifest does not declare: nowhere",
    "opens with no page": "NOT OK   a panel: ui/open was not answered with a page",
    "answers a tap with the same page": "NOT OK   a panel: a tap on add was answered with the same page",
    "opens an undeclared panel": "NOT OK   a panel: a tap's open names elsewhere, a panel the manifest does not declare",
    "opens its island page": "NOT OK   a panel: a tap's open names counter, a panel of the island",
    "opens its settings without asking": "NOT OK   an older app: a tap's open names the settings panel settings, "
    "which an app without ui.open.settings does not open",
    "puts a section in its settings": "NOT OK   an older app: the page of settings holds a heading that "
    "starts a section, which an app without ui.sections draws as a plain heading: ask supports first",
}

# A page whose block, or a row of whose list, has an id that is no name: how
# the tool names it, the id, and the one line the script must print. The app
# refuses the whole page for any of them, as HomeSpeaker 1.27.1's Settings
# page was refused for "installHook:claudeCode".
REFUSED = ": Vitruvian refuses the whole page"
CHARS = "ASCII letters, digits, '.', '-' and '_' only"
ILL_NAMED = [
    (
        how,
        named,
        f"NOT OK   a panel: the page of counter has {what} {named!r}{where}, "
        f"which is not a valid name ({rule}){REFUSED}",
    )
    for how, what, where in (
        ("names a block", "block id", ""),
        ("names a plain row", "block id", ""),
        ("names a row of a list", "list row id", " in list 'hooks'"),
    )
    for named, rule in (
        ("installHook:claudeCode", CHARS),
        ("caf\u00e9", CHARS),
        ("the latest", CHARS),
        ("a" * 129, "at most 128 characters"),
        ("hooks..claude", "no two '.' together"),
        (".hooks", "no '.' at either end"),
        ("hooks.", "no '.' at either end"),
        ("", "at least one character"),
    )
] + [
    (
        "leaves a row of a list unnamed",
        None,
        "NOT OK   a panel: the page of counter has a row "
        f"in list 'hooks' whose id is missing or not text{REFUSED}",
    ),
]

# Ids that are names, at the edges of the rule: they pass.
WELL_NAMED = [
    (how, named)
    for how in ("names a block", "names a plain row", "names a row of a list")
    for named in ("a" * 128, "install-hook.claude_code", "x", "0.1-b_2")
]

# A tap answered with `open` alone, and no page, passes when it names a
# window or, on an app that names ui.open.settings, the settings panel.
OPENS_WELL = {
    "opens a window": "ok       a panel: counter: a page of 2 blocks, and the window log after a tap on add",
    "opens its settings": "ok       a panel: counter: a page of 2 blocks, and the settings panel settings after a tap on add",
}

# A tool of protocol 2 written with no kit, which shows a status and draws a
# choice, and may draw chips, a section and help. It goes wrong in the way
# BROKEN_HOW names, or does well when it is "shows a status well". It asks
# what the app has, as a tool must: an app that names no ui.status is sent
# none, and one that names no ui.chips or ui.sections is sent switches and
# words, unless the way it goes wrong is to send them all the same.
STATUS_TOOL = """
import json, os, sys
how = os.environ["BROKEN_HOW"]
features = []
asked = 0
def send(message):
    sys.stdout.write(json.dumps(message) + "\\n")
    sys.stdout.flush()
def status(state, **more):
    global asked
    asked += 1
    send({"jsonrpc": "2.0", "id": "s%d" % asked, "method": "ui/status", "params": dict(more, state=state)})
def page():
    options = [{"value": "green", "title": "Green"},
               {"value": "breathe green", "title": {"en": "Pulsing green", "de": "Pulsierendes Grün"}}]
    if how == "draws two options alike":
        options.append({"value": "green", "title": "Green again"})
    if how == "draws a choice of nothing":
        options = []
    if "ui.choice" in features or how.startswith("draws"):
        pick = {"type": "choice", "id": "light", "title": "Light", "value": "green", "options": options,
                "fallback": "Light: Green"}
    else:
        pick = {"type": "field", "id": "light", "title": "Light", "value": "green"}
    blocks = [{"type": "text", "text": "Pressed %d times" % asked}, pick]
    chips = [{"value": "whatsapp", "title": "WhatsApp", "on": True},
             {"value": "signal", "title": {"en": "Signal", "de": "Signal"}, "on": False}]
    if how == "draws two chips alike":
        chips.append({"value": "whatsapp", "title": "WhatsApp again", "on": False})
    if how == "draws chips of nothing":
        chips = []
    if how == "draws chips whose chip is not on or off":
        del chips[0]["on"]
    if how == "draws chips well" and "ui.chips" not in features:
        blocks += [{"type": "toggle", "id": c["value"], "title": c["title"], "value": c["on"]} for c in chips]
    elif "chips" in how:
        drawn = {"type": "chips", "title": "Networks", "options": chips, "fallback": "Networks: WhatsApp"}
        if how != "draws chips with no id":
            drawn["id"] = "networks"
        blocks.append(drawn)
    well = how == "sections and help well" and "ui.sections" in features
    if how == "starts a section whatever the app has" or well:
        blocks.insert(0, {"type": "heading", "text": "Lights", "section": True})
    if how == "says help whatever the app has" or well:
        blocks.append({"type": "toggle", "id": "pause", "title": "Pause", "value": False,
                       "help": "Pauses what is playing."})
    if how == "says section: false to an older app":
        blocks.insert(0, {"type": "heading", "text": "Lights", "section": "ui.sections" in features})
    if how == "says help with a number":
        blocks.append({"type": "toggle", "id": "pause", "title": "Pause", "value": False, "help": 5})
    if how == "sections and help well" and not well:
        blocks += [{"type": "heading", "text": "Lights"},
                   {"type": "toggle", "id": "pause", "title": "Pause", "value": False},
                   {"type": "text", "text": "Pauses what is playing.", "style": "caption"}]
    return {"blocks": blocks}
for line in sys.stdin:
    message = json.loads(line)
    method = message.get("method")
    if method == "initialize":
        features = message["params"].get("features", [])
        send({"jsonrpc": "2.0", "id": message["id"], "result": {"protocolVersion": "2", "toolVersion": "0"}})
    elif method == "command/run":
        if message["params"]["command"] != "hello":
            send({"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32602, "message": "no such command"}})
            continue
        if how == "names a state there is not":
            status("broken")
        elif how == "says it in French alone":
            status("failure", text={"fr": "main est rouge"})
        elif how == "names a glyph that is no name":
            status("busy", icon=7)
        elif how == "counts from before 1970":
            status("busy", since=-1)
        elif how == "says its few words with a number":
            status("busy", activity=3)
        elif how == "says a few words" and "ui.status.activity" in features:
            status("busy", text="Checks are running", activity="3")
            status("busy", since=1760450400.5)
        elif "ui.status" in features:
            status("busy", icon="arrow.triangle.branch", text={"en": "Working", "fr": "En cours"})
            status("none")
        elif how in ("asks an older app", "dies when refused"):
            status("busy")
        elif how == "keeps asking an older app":
            for _ in range(8):
                status("busy")
        send({"jsonrpc": "2.0", "id": message["id"], "result": {}})
    elif method == "ui/open":
        send({"jsonrpc": "2.0", "id": message["id"], "result": {"tree": page()}})
    elif method == "ui/event":
        send({"jsonrpc": "2.0", "id": message["id"], "result": {"keep": True}})
    elif method == "shutdown":
        sys.exit(0)
    elif method is None and message.get("error", {}).get("code") == -32601 and how == "dies when refused":
        sys.exit(1)
"""

# How a tool that shows a status or draws a choice goes wrong, and the line
# the script must print.
BROKEN_STATUS = {
    "names a state there is not": "NOT OK   a command: ui/status with params that are not its own",
    "says it in French alone": "NOT OK   a command: ui/status with params that are not its own",
    "names a glyph that is no name": "NOT OK   a command: ui/status with params that are not its own",
    "counts from before 1970": "NOT OK   a command: ui/status with params that are not its own",
    "says its few words with a number": "NOT OK   a command: ui/status with params that are not its own",
    "draws two options alike": "NOT OK   a panel: ui/open was not answered with a page",
    "draws a choice of nothing": "NOT OK   a panel: ui/open was not answered with a page",
    "draws two chips alike": "NOT OK   a panel: ui/open was not answered with a page",
    "draws chips of nothing": "NOT OK   a panel: ui/open was not answered with a page",
    "draws chips with no id": "NOT OK   a panel: ui/open was not answered with a page",
    "draws chips whose chip is not on or off": "NOT OK   a panel: ui/open was not answered with a page",
    "says help with a number": "NOT OK   a panel: ui/open was not answered with a page",
    "draws chips whatever the app has": "NOT OK   an older app: the page of lights holds chips, which an "
    "app without ui.chips draws as their fallback text",
    "starts a section whatever the app has": "NOT OK   an older app: the page of lights holds a heading "
    "that starts a section, which an app without ui.sections draws as a plain heading: ask supports first",
    "says help whatever the app has": "NOT OK   an older app: the page of lights holds help on a toggle, "
    "which an app without ui.sections leaves out: ask supports first, and send a text after the control",
    "dies when refused": "NOT OK   an older app: the tool did not carry on after an app that has no "
    "ui/status refused it with -32601",
    "keeps asking an older app": "NOT OK   an older app: the tool went on sending ui/status to an app that "
    "answered it with -32601",
}

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
    "wrong version": "NOT OK   handshake: the tool picked a version that was not offered",
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
    the read; `a_line_always_waiting` holds the rule without the timing. When
    it counted, the tool is started once more as an older app's, and the same
    two things may be said of that run.
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
    # The line for the shutdown check, and the one for the older app, which
    # starts the tool once more and so meets the same program left behind.
    said = {
        name: next(
            (line for line in printed.splitlines() if line[9:].startswith(name)), ""
        )
        for name in ("shutdown", "an older app")
    }
    writing = f"still writing {conformance.EXIT_SECONDS} seconds after it exited"
    caught = status == 1 and said["shutdown"] == f"NOT OK   shutdown: {writing}"
    counted = said["shutdown"].startswith(
        "ok       shutdown: exited with 0, after "
    ) and (
        (status == 0 and said["an older app"].startswith("ok       an older app: "))
        or (status == 1 and said["an older app"] == f"NOT OK   an older app: {writing}")
    )
    problems = []
    if not (caught or counted):
        problems.append(f"a tool that never stops writing:\n{printed}")
    if took > SLOWEST_SECONDS:
        problems.append(
            f"a tool that never stops writing held the script {took:.1f} seconds"
        )
    return problems


def panels(manifest):
    """A tool of protocol 2 that draws well passes the panel check, and one
    that goes wrong in each way is caught by it."""
    problems = []
    manifest = dict(manifest)
    manifest["protocol"] = "2"
    manifest["runtime"] = {"kind": "external", "exec": "panel.py"}
    manifest["contributes"] = dict(manifest["contributes"])
    manifest["contributes"]["panels"] = [
        {"id": "counter", "title": {"en": "Counter"}, "placement": "island"},
        {"id": "settings", "title": {"en": "Counter"}, "placement": "settings"},
        {"id": "log", "title": {"en": "Log"}, "placement": "window"},
    ]
    with tempfile.TemporaryDirectory() as folder:
        with open(
            os.path.join(folder, "vitruvian-tool.json"), "w", encoding="utf-8"
        ) as handle:
            json.dump(manifest, handle)
        with open(os.path.join(folder, "panel.py"), "w", encoding="utf-8") as handle:
            handle.write(BROKEN_PANEL_TOOL)
        os.environ["BROKEN_HOW"] = "draws well"
        status, printed = check(folder)
        wanted = (
            "ok       a panel: counter: a page of 2 blocks, and a new page after a tap on add; "
            "settings: a page of 2 blocks; log: a page of 2 blocks"
        )
        if (
            status != 0
            or wanted not in printed
            or "ok       handshake: version 2" not in printed
        ):
            problems.append(f"a tool that draws well does not pass:\n{printed}")
        for how, line in OPENS_WELL.items():
            os.environ["BROKEN_HOW"] = how
            status, printed = check(folder)
            if status != 0 or line not in printed:
                problems.append(f"a tool that {how} does not pass:\n{printed}")
        for how, line in BROKEN_PANEL.items():
            os.environ["BROKEN_HOW"] = how
            status, printed = check(folder)
            failed = [
                text for text in printed.splitlines() if text.startswith("NOT OK")
            ]
            if status != 1 or len(failed) != 1 or not failed[0].startswith(line):
                problems.append(f"a tool that {how} is not caught:\n{printed}")
        for how, named, line in ILL_NAMED:
            os.environ["BROKEN_HOW"] = how
            os.environ["BROKEN_ID"] = named or ""
            status, printed = check(folder)
            failed = [
                text for text in printed.splitlines() if text.startswith("NOT OK")
            ]
            if status != 1 or failed != [line]:
                problems.append(
                    f"a tool that {how} {named!r} is not caught as\n{line}\nbut:\n{printed}"
                )
        for how, named in WELL_NAMED:
            os.environ["BROKEN_HOW"] = how
            os.environ["BROKEN_ID"] = named
            status, printed = check(folder)
            if (
                status != 0
                or "ok       a panel: counter: a page of 3 blocks" not in printed
            ):
                problems.append(
                    f"a tool that {how} {named!r} does not pass:\n{printed}"
                )
        del os.environ["BROKEN_ID"]
    return problems


def statuses(manifest):
    """A tool that shows a status and draws a choice passes, against this
    app and an older one; one that goes wrong in each way is caught by the
    check meant for it; and one whose manifest declares no status is told."""
    problems = []
    manifest = dict(manifest)
    manifest["protocol"] = "2"
    manifest["uses"] = []
    manifest["runtime"] = {"kind": "external", "exec": "status.py"}
    manifest["contributes"] = dict(manifest["contributes"])
    manifest["contributes"]["panels"] = [
        {"id": "lights", "title": {"en": "Lights"}, "placement": "island"}
    ]
    manifest["contributes"]["status"] = {"placement": "island"}
    with tempfile.TemporaryDirectory() as folder:

        def write(declared):
            with open(
                os.path.join(folder, "vitruvian-tool.json"), "w", encoding="utf-8"
            ) as handle:
                json.dump(declared, handle)

        write(manifest)
        with open(os.path.join(folder, "status.py"), "w", encoding="utf-8") as handle:
            handle.write(STATUS_TOOL)

        os.environ["BROKEN_HOW"] = "shows a status well"
        status, printed = check(folder)
        wanted = [
            "ok       a command: hello: ran, and set the status: busy, none",
            "ok       a panel: lights: a page of 2 blocks",
            "ok       refusals: 2 refused",
            "ok       an older app: answered the hello, ran hello, drew lights and left with 0; "
            "it sent no ui/status",
        ]
        if status != 0 or not all(piece in printed for piece in wanted):
            problems.append(
                f"a tool that shows a status well does not pass:\n{printed}"
            )

        os.environ["BROKEN_HOW"] = "asks an older app"
        status, printed = check(folder)
        wanted = (
            "ok       an older app: answered the hello, ran hello, drew lights and left with 0; "
            "1 ui/status refused with -32601, as an app before 3.48 does"
        )
        if status != 0 or wanted not in printed:
            problems.append(
                f"a tool that an older app refuses, and that carries on, does not pass:\n{printed}"
            )

        os.environ["BROKEN_HOW"] = "draws a choice whatever the app has"
        status, printed = check(folder)
        wanted = "its page holds a choice, which that app draws as its fallback text"
        if status != 0 or wanted not in printed:
            problems.append(
                f"a tool that sends an older app a choice is not told so:\n{printed}"
            )

        for how in (
            "draws chips well",
            "sections and help well",
            "says section: false to an older app",
        ):
            os.environ["BROKEN_HOW"] = how
            status, printed = check(folder)
            wanted = [
                "ok       a panel: lights: a page of",
                "ok       an older app: answered the hello, ran hello, drew lights and left with 0",
            ]
            if status != 0 or not all(piece in printed for piece in wanted):
                problems.append(
                    f"a tool that {how}, asking what the app has, does not pass:\n{printed}"
                )

        for how, line in BROKEN_STATUS.items():
            os.environ["BROKEN_HOW"] = how
            started = time.monotonic()
            status, printed = check(folder)
            took = time.monotonic() - started
            failed = [
                text for text in printed.splitlines() if text.startswith("NOT OK")
            ]
            if status != 1 or len(failed) != 1 or not failed[0].startswith(line):
                problems.append(f"a tool that {how} is not caught:\n{printed}")
            if took > SLOWEST_SECONDS:
                problems.append(f"a tool that {how} held the script {took:.1f} seconds")

        undeclared = dict(manifest)
        undeclared["contributes"] = {
            key: value
            for key, value in manifest["contributes"].items()
            if key != "status"
        }
        write(undeclared)
        os.environ["BROKEN_HOW"] = "shows a status well"
        status, printed = check(folder)
        failed = [text for text in printed.splitlines() if text.startswith("NOT OK")]
        wanted = (
            "NOT OK   a command: ui/status from a tool whose manifest declares no status. "
            "The app answers it with -32602: add `contributes.status`"
        )
        if status != 1 or failed != [wanted]:
            problems.append(
                f"a tool that sets a status its manifest does not declare is not told:\n{printed}"
            )

        # A few words with the status: drawn for a tool that declares them,
        # left out, and failed here, for one that does not.
        write(manifest)
        os.environ["BROKEN_HOW"] = "says a few words"
        status, printed = check(folder)
        failed = [text for text in printed.splitlines() if text.startswith("NOT OK")]
        wanted = (
            "NOT OK   a command: ui/status with words from a tool whose manifest does not "
            "declare them. The app draws the mark and leaves the words out: add "
            '"activity": true to contributes.status'
        )
        if status != 1 or failed != [wanted]:
            problems.append(
                f"a tool that sends words its manifest does not declare is not told:\n{printed}"
            )
        declared = dict(manifest)
        declared["contributes"] = dict(manifest["contributes"])
        declared["contributes"]["status"] = {"placement": "island", "activity": True}
        write(declared)
        status, printed = check(folder)
        wanted = [
            "ok       a command: hello: ran, and set the status: busy, busy",
            "ok       an older app: answered the hello, ran hello, drew lights and left with 0; "
            "it sent no ui/status",
        ]
        if status != 0 or not all(piece in printed for piece in wanted):
            problems.append(
                f"a tool that declares its words and sends them does not pass:\n{printed}"
            )
    return problems


# A tool of protocol 2 written with no kit, which declares a slot, shows a
# notice and asks for its slot. It goes wrong in the way BROKEN_HOW names, or
# does well when it is "docks well": it asks what the app has, and sends an
# app without notify.notice a short message and one without ui.slot nothing.
SLOT_TOOL = """
import json, os, sys
how = os.environ["BROKEN_HOW"]
features = []
told = []
def send(message):
    sys.stdout.write(json.dumps(message) + "\\n")
    sys.stdout.flush()
for line in sys.stdin:
    message = json.loads(line)
    method = message.get("method")
    if method == "initialize":
        features = message["params"].get("features", [])
        send({"jsonrpc": "2.0", "id": message["id"], "result": {"protocolVersion": "2", "toolVersion": "0"}})
    elif method == "ui/slot":
        told.append(message["params"])
    elif method == "command/run":
        if message["params"]["command"] != "hello":
            send({"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32602, "message": "no such command"}})
            continue
        if "notify.notice" in features or how == "sends a notice whatever the app has":
            params = {"icon": "bell", "title": "Done", "detail": "the tests pass", "system": True}
            if how == "says a notice with a number":
                params["title"] = 5
            send({"jsonrpc": "2.0", "id": "n", "method": "notify/notice", "params": params})
        else:
            send({"jsonrpc": "2.0", "id": "n", "method": "notify/hud", "params": {"icon": "bell", "message": "Done"}})
        if "ui.slot" in features or how == "docks whatever the app has":
            send({"jsonrpc": "2.0", "id": "d", "method": "ui/dock"})
        send({"jsonrpc": "2.0", "id": message["id"], "result": {}})
    elif method == "shutdown":
        sys.exit(0)
"""

# How a tool that shows a notice or docks goes wrong, and the line the script
# prints for it.
BROKEN_SLOT = {
    "says a notice with a number": "NOT OK   a command: notify/notice with params that are not its own",
    "sends a notice whatever the app has": "NOT OK   an older app: notify/notice to an app whose hello does "
    "not name notify.notice",
    "docks whatever the app has": "NOT OK   an older app: ui/dock to an app whose hello does not name ui.slot",
}


def slots(manifest):
    """A tool that declares a slot, shows a notice and docks passes, against
    this app and an older one; one that goes wrong in each way is caught; and
    one that docks with no slot declared is told."""
    problems = []
    manifest = dict(manifest)
    manifest["protocol"] = "2"
    manifest["uses"] = ["notify"]
    manifest["runtime"] = {"kind": "external", "exec": "slot.py"}
    manifest["contributes"] = {
        "commands": manifest["contributes"]["commands"],
        "slot": {"placement": "agents"},
    }
    with tempfile.TemporaryDirectory() as folder:

        def write(declared):
            with open(
                os.path.join(folder, "vitruvian-tool.json"), "w", encoding="utf-8"
            ) as handle:
                json.dump(declared, handle)

        write(manifest)
        with open(os.path.join(folder, "slot.py"), "w", encoding="utf-8") as handle:
            handle.write(SLOT_TOOL)

        os.environ["BROKEN_HOW"] = "docks well"
        status, printed = check(folder)
        wanted = [
            "ok       handshake: version 2, tool 0, and told where its slot is",
            "ok       a command: hello: ran, and asked for its slot",
            "ok       refusals: 2 refused",
            "ok       an older app: answered the hello, ran hello and left with 0",
        ]
        if status != 0 or not all(piece in printed for piece in wanted):
            problems.append(f"a tool that docks well does not pass:\n{printed}")

        for how, line in BROKEN_SLOT.items():
            os.environ["BROKEN_HOW"] = how
            status, printed = check(folder)
            failed = [
                text for text in printed.splitlines() if text.startswith("NOT OK")
            ]
            if status != 1 or len(failed) != 1 or not failed[0].startswith(line):
                problems.append(f"a tool that {how} is not caught:\n{printed}")

        undeclared = dict(manifest)
        undeclared["contributes"] = {"commands": manifest["contributes"]["commands"]}
        write(undeclared)
        os.environ["BROKEN_HOW"] = "docks well"
        status, printed = check(folder)
        failed = [text for text in printed.splitlines() if text.startswith("NOT OK")]
        wanted = (
            "NOT OK   a command: ui/dock from a tool whose manifest declares no slot. "
            "The app answers it with -32602: add `contributes.slot`"
        )
        if status != 1 or failed != [wanted]:
            problems.append(
                f"a tool that docks with no slot declared is not told:\n{printed}"
            )
    return problems


def the_hello(manifest):
    """What the script says at hello: what this app has, and to an older
    app's tool nothing of it."""
    problems = []

    class Kept:
        def __init__(self):
            self.sent = []

        def send(self, message):
            self.sent.append(message)

        def receive(self, deadline, seconds, leaving=False):
            return {
                "jsonrpc": "2.0",
                "id": 1,
                "result": {"protocolVersion": "1", "toolVersion": "0"},
            }

    for features, wanted in (
        (
            conformance.FEATURES,
            [
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
            ],
        ),
        (None, None),
    ):
        link = Kept()
        conformance.Run(link, manifest, "/tmp/data", features=features).handshake()
        if link.sent[0]["params"].get("features") != wanted:
            problems.append(f"the hello says {link.sent[0]['params']!r}")
    if "features" not in conformance.Run(Kept(), manifest, "").hello():
        problems.append("the hello of this app names no features")
    return problems


def answers_with_its_page(folder):
    """The reference tool of protocol 2 answers a press with the next page,
    as the guide does, and sends nothing with `ui/render`. The script's
    printed line reads the same either way, so this asks the run itself:
    a new page after the tap, and none pushed, means it came in the answer."""
    with open(os.path.join(folder, "vitruvian-tool.json"), encoding="utf-8") as handle:
        manifest = json.load(handle)
    program = os.path.join(folder, manifest["runtime"]["exec"])
    with tempfile.TemporaryDirectory() as data_folder:
        link = conformance.Link([sys.executable, program], data_folder)
        try:
            run = conformance.Run(link, manifest, data_folder)
            run.handshake()
            said = run.a_panel()
            run.shutdown()
        except conformance.Failure as failure:
            return [f"the reference tool of protocol 2 failed: {failure}"]
        finally:
            link.close()
    if "a new page after a tap" not in said:
        return [
            f"the reference tool of protocol 2 drew no new page after a tap: {said}"
        ]
    if run.rendered:
        return [
            "the reference tool of protocol 2 sent its page with ui/render, "
            "not in its answer to the tap"
        ]
    return []


def main():
    problems = []

    status, printed = check(REFERENCE, "--expect-refusal")
    wanted = [
        "ok       handshake",
        "ok       a command: hello: ran",
        "ok       unknown",
        "1 refused",
        "exited with 0",
        "ok       an older app: answered the hello, ran hello and left with 0; it sent no ui/status",
    ]
    if status != 0 or not all(piece in printed for piece in wanted):
        problems.append(f"the reference tool does not pass:\n{printed}")

    status, printed = check(REFERENCE_2, "--expect-refusal")
    wanted = [
        "ok       handshake: version 2, tool 0.1.0",
        "ok       a command: hello: ran",
        "ok       unknown",
        "ok       a panel: hello: a page of 2 blocks, and a new page after a tap on press",
        "1 refused",
        "exited with 0",
        "ok       an older app: answered the hello, ran hello, drew hello and left with 0; "
        "it sent no ui/status",
    ]
    if status != 0 or not all(piece in printed for piece in wanted):
        problems.append(f"the reference tool of protocol 2 does not pass:\n{printed}")
    problems += answers_with_its_page(REFERENCE_2)

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
    problems += panels(manifest)
    problems += statuses(manifest)
    problems += slots(manifest)
    problems += the_hello(manifest)
    problems += a_line_always_waiting()

    for problem in problems:
        print(problem, file=sys.stderr)
    print("conformance: " + ("FAILED" if problems else "OK"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
