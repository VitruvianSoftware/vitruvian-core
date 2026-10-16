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

"""The built HomeSpeaker tool is a tool the app can add, and it speaks the protocol.

    conformance_test.py <built vitruvian-tool.json> <conformance.py> <vitruvian-tool>

Runs `vitruvian-tool validate` on the built folder, then the SDK's
conformance script, which plays the app to the real program: the handshake,
the `sayClipboard` command (answered with a refusal: the extension has no
speaker picked and This Mac off, so it is not set up), an unknown command,
the island panel opened and its page read, the refusals, and a clean exit.

The program runs in a scratch folder of its own: `HOME` and
`CFFIXED_USER_HOME` are a home in it, `HOMESPEAKER_DATA_FOLDER` a data
folder in it, `HOMESPEAKER_PROGRAM` set and empty keeps it off the
HomeSpeaker app Launch Services would find on this Mac, and
`HOMESPEAKER_MESSAGE_PREFIX` is this run's own, so a HomeSpeaker on this
Mac hears nothing of it. Before anything runs, the program's hidden
`--where` flag must name that data folder. `HOMESPEAKER_PROGRAM=""` is what
keeps the program from finding, and so from ever offering to quit, a real
HomeSpeaker app running on this Mac: the first page each run shows is
checked to hold no "Quit the app" button and no old-app line.

Then it plays the app itself, over the same JSON-RPC on stdin and stdout,
with the conformance script's own link and checks (imported, not copied):
the island and each of the five settings sections are opened, every page
is held to the protocol's limits (`is_tree`: the most blocks, the most
bytes, the choice rules), switches, choices and fields are changed, and the
settings file and the secrets file are read back from the data folder. The
quiet hours are a choice of half hours for this app, which has `choice`;
a time that is not HH:mm is typed, and refused, by an app from before 3.48,
which has no `features` and so is given the typed field.
Nothing is written until the tool has said, on its Files rows, that both
files are in that folder. The island draws its controls because the
extension is installed by definition; no HomeSpeaker program is run. Only
a block on the page the tool last drew is acted on.

Last, nothing was written where the app keeps its files: the scratch
home's `.gemini` holds none of the app's settings, history or monitor
status, and the choice file, which both sides share by design, holds only
the extension's own block, naming the scratch folder.
"""

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import uuid

# The five sections of the settings panel (Pages.Section), in order.
SECTIONS = ["general", "speakers", "monitor", "agents", "googleCloud"]
# Longer than the conformance script's two seconds: a section reads the
# agents' files, and a busy CI Mac is slow to start a Swift program.
SECONDS = 15

# The app's own files in ~/.gemini, which the extension must never write.
APP_FILES = [
    "speaker_broadcast.json",
    "speaker_history.json",
    "speaker_monitor_status.json",
]
# The choice file both sides share: the extension writes its own block.
DOOR_FILE = "speaker_door.json"
# The conformance script's line for the command, refused because the
# extension is not set up (HomeSpeakerTool.notSetUp).
NOT_SET_UP = "sayClipboard: refused, Set up HomeSpeaker first"


def main():
    manifest, conformance, validate = sys.argv[1:4]
    built = os.path.dirname(os.path.abspath(manifest))
    # Bazel lays the built folder out as links; the app runs a copy, and
    # `validate` refuses a program that is a link out of the folder. So the
    # folder is copied, as the app copies it, and the copy is judged.
    scratch = tempfile.mkdtemp(dir=os.environ.get("TEST_TMPDIR"))
    folder = os.path.join(scratch, "homespeaker")
    shutil.copytree(built, folder, symlinks=False)
    home = os.path.join(scratch, "home")
    os.makedirs(home)
    data = os.path.join(scratch, "data")
    # A home of its own: the app's files are in ~/.gemini, and with this
    # Mac's home the tool could find them. CFFIXED_USER_HOME is what
    # NSHomeDirectory() reads. HOMESPEAKER_DATA_FOLDER is where the
    # extension keeps its settings and sign-ins. Launch Services would still
    # know this Mac's HomeSpeaker app by its bundle id, whatever the home:
    # HOMESPEAKER_PROGRAM, set and empty, keeps the tool off it.
    # HOMESPEAKER_MESSAGE_PREFIX: the program listens and posts under a
    # prefix of this run's own, so a HomeSpeaker extension running on this
    # Mac hears nothing of it.
    env = dict(
        os.environ,
        HOME=home,
        CFFIXED_USER_HOME=home,
        HOMESPEAKER_DATA_FOLDER=data,
        HOMESPEAKER_PROGRAM="",
        HOMESPEAKER_MESSAGE_PREFIX=f"test.{uuid.uuid4()}.homespeaker",
    )
    program = os.path.join(folder, "bin", "tool")
    try:
        said = where(program, data, env)
    except E2EFailure as failure:
        print(f"--- where: NOT OK: {failure}")
        return 1
    print(f"--- where: {said}")
    failed = 0
    for name, command in [
        ("validate", [os.path.abspath(validate), "validate", folder]),
        ("conformance", [sys.executable, os.path.abspath(conformance), folder]),
    ]:
        done = subprocess.run(
            command, capture_output=True, text=True, timeout=180, check=False, env=env
        )
        print(f"--- {name}: exit {done.returncode}\n{done.stdout}{done.stderr}")
        if done.returncode != 0:
            failed += 1
        # The command must have been refused, not run: the extension has no
        # speaker and This Mac is off, and a run would mean it found
        # something to speak on, which no test may drive.
        if name == "conformance" and NOT_SET_UP not in done.stdout:
            print(
                "the sayClipboard command was not refused as not set up: "
                "the program found something to speak on"
            )
            failed += 1
    if failed:
        print(f"{failed} of 2 checks failed")
        return 1
    try:
        said = end_to_end(load(conformance), folder, data, env)
    except E2EFailure as failure:
        print(f"--- end to end: NOT OK: {failure}")
        return 1
    print("--- end to end: ok\n" + "\n".join(said))
    try:
        said = nothing_outside(home, scratch)
    except E2EFailure as failure:
        print(f"--- the app's files: NOT OK: {failure}")
        return 1
    print(f"--- the app's files: {said}")
    print(
        "the built HomeSpeaker tool validates, passes the conformance script, "
        "draws and saves its pages end to end, and keeps to its scratch folder"
    )
    return 0


def where(program, data, env):
    """The folder the program keeps its files in, by its hidden `--where`
    flag, must be the scratch data folder: checked before anything runs."""
    done = subprocess.run(
        [program, "--where"],
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
        env=env,
    )
    if done.returncode != 0:
        raise E2EFailure(
            f"--where exited {done.returncode}: {done.stdout}{done.stderr}"
        )
    named = done.stdout.strip()
    if os.path.realpath(named) != os.path.realpath(data):
        raise E2EFailure(f"--where names {named!r}, not the scratch data folder {data}")
    return f"the program keeps its files in {named}"


def nothing_outside(home, scratch):
    """Nothing of the app's was written under the scratch home's `.gemini`:
    not its settings, its history or its monitor status. The choice file
    may be there, since both sides share it, but holds only the extension's
    block, and that names the scratch folder."""
    gemini = os.path.join(home, ".gemini")
    for name in APP_FILES:
        if os.path.exists(os.path.join(gemini, name)):
            raise E2EFailure(
                f"{os.path.join(gemini, name)} was written: that is the app's file"
            )
    door = os.path.join(gemini, DOOR_FILE)
    if not os.path.exists(door):
        return f"nothing in {gemini}"
    with open(door, encoding="utf-8") as handle:
        record = json.load(handle)
    if not set(record) <= {"version", "extension"}:
        raise E2EFailure(
            f"{door} holds more than the extension's block: {sorted(record)}"
        )
    entry = record.get("extension") or {}
    inside = os.path.realpath(scratch) + os.sep
    for key in ("program", "data_folder"):
        path = entry.get(key)
        if not isinstance(path, str) or not os.path.realpath(path).startswith(inside):
            raise E2EFailure(
                f"{door}: the extension's {key} is {path!r}, not in {scratch}"
            )
    return f"none of the app's files in {gemini}; {DOOR_FILE} holds only the extension's block"


class E2EFailure(Exception):
    """The tool, driven page by page, did not do what it should."""


def load(path):
    """The SDK's conformance script as a module: its link, its checks and
    its limits, so this test holds the tool to the same rules."""
    spec = importlib.util.spec_from_file_location("vitruvian_conformance", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def words(value):
    """Every string in a block, wherever the protocol puts it: titles,
    subtitles, values, and each language of a localised text."""
    if isinstance(value, str):
        return [value]
    if isinstance(value, dict):
        return [w for v in value.values() for w in words(v)]
    if isinstance(value, list):
        return [w for v in value for w in words(v)]
    return []


def says(tree, text):
    return any(text in w for block in tree["blocks"] for w in words(block))


def block(tree, block_id):
    return next((b for b in tree["blocks"] if b.get("id") == block_id), None)


# The extension's offer to quit an app older than 1.19 (Pages.DoorWords,
# OtherAppPlan.Step.oldAppWarning). Never drawn here: no app is found.
QUIT_AGAIN = "door.quitAgain"
OLD_APP = "This copy of the app is older than 1.19"


def offers_no_quit(tree, where):
    """The page holds nothing that would quit an app: with no app found, a
    HomeSpeaker that happens to run on this Mac must never be offered."""
    if block(tree, QUIT_AGAIN) is not None or says(tree, OLD_APP):
        raise E2EFailure(
            f"{where}: the page offers to quit a HomeSpeaker app, though none was found"
        )
    return tree


class Driver:
    """The app's side, page by page, through the conformance script's Run."""

    def __init__(self, conf, run):
        self.conf = conf
        self.run = run
        self.pages = []
        # The page each panel shows now.
        self.current = {}

    def check(self, tree, where):
        conf = self.conf
        if tree is None or not conf.is_tree(tree):
            size = len(json.dumps(tree, separators=(",", ":")).encode()) if tree else 0
            count = len(tree.get("blocks", [])) if isinstance(tree, dict) else 0
            raise E2EFailure(
                f"{where}: not a page within the protocol's limits "
                f"({count} blocks of at most {conf.MAX_BLOCKS}, "
                f"{size} bytes of at most {conf.MAX_TREE_BYTES})"
            )
        self.pages.append(
            f"{where}: {len(tree['blocks'])} blocks, "
            f"{len(json.dumps(tree, separators=(',', ':')).encode())} bytes"
        )
        return tree

    def ask(self, method, params, where):
        try:
            kind, message = self.run.answer(self.run.request(method, params), SECONDS)
        except self.conf.Failure as failure:
            raise E2EFailure(f"{where}: {failure}") from None
        if kind != "result" or not isinstance(message.get("result"), dict):
            raise E2EFailure(f"{where}: answered with {message!r}")
        return message["result"]

    def open(self, panel):
        result = self.ask("ui/open", {"panel": panel}, f"open {panel}")
        tree = self.check(result.get("tree", self.run.rendered.get(panel)), panel)
        self.current[panel] = tree
        return tree

    def act(self, panel, block_id, event, value=None, keep_ok=False):
        params = {"panel": panel, "block": block_id, "event": event}
        if value is not None:
            params["value"] = value
        where = f"{panel}: {event} {block_id}" + (
            f" = {value!r}" if value is not None else ""
        )
        # A page the tool sent by itself since is the one on screen.
        shown = self.run.rendered.pop(panel, None) or self.current.get(panel)
        if shown is None or block(shown, block_id) is None:
            raise E2EFailure(f"{where}: the page shown has no such block")
        result = self.ask("ui/event", params, where)
        if "tree" not in result:
            if keep_ok and result.get("keep") is True:
                return None
            raise E2EFailure(f"{where}: answered with no page: {result!r}")
        tree = self.check(result["tree"], where)
        self.current[panel] = tree
        return tree

    def section(self, name):
        tree = self.act("settings", "section", "change", name)
        picker = block(tree, "section")
        if picker is None or picker.get("value") != name:
            raise E2EFailure(
                f"settings: the section picker does not show {name}: {picker!r}"
            )
        return tree


def end_to_end(conf, folder, data, env):
    """Opens every page the app can show and changes what it can save, in
    the data folder `data`. Returns what was done, a line each."""
    with open(os.path.join(folder, "vitruvian-tool.json"), encoding="utf-8") as handle:
        manifest = json.load(handle)
    program = os.path.join(folder, manifest["runtime"]["exec"])
    settings = os.path.join(data, "settings.json")
    secrets = os.path.join(data, "secrets.json")
    # The folder the link starts the program in, which the hello names: the
    # variable wins over it, so the files are in `data`.
    started_in = tempfile.mkdtemp(dir=os.environ.get("TEST_TMPDIR"))
    # The kit's link starts the program with this process's environment.
    os.environ.update(env)
    link = conf.Link([program], started_in)
    said = []
    try:
        run = conf.Run(link, manifest, started_in)
        said.append("handshake: " + run.handshake())
        app = Driver(conf, run)

        # Before anything is written: the tool must be using this folder.
        offers_no_quit(app.open("settings"), "settings, first page")
        cloud = app.section("googleCloud")
        for path in (settings, secrets):
            if not says(cloud, path):
                raise E2EFailure(
                    f"Files does not name {path}: the tool is not using the test's "
                    "data folder, and nothing may be written"
                )

        for name in SECTIONS:
            app.section(name)
        said.append("settings: " + ", ".join(SECTIONS) + " each drawn")

        # General: a switch, and the quiet hours picked from half hours.
        general = app.section("general")
        for block_id in ("quietStart", "quietEnd"):
            drawn = block(general, block_id)
            if drawn is None or drawn.get("type") != "choice":
                raise E2EFailure(
                    f"settings: {block_id} is not a choice for an app that has one: {drawn!r}"
                )
        app.act("settings", "quiet", "toggle", True)
        app.act("settings", "quietStart", "change", "23:00")
        app.act("settings", "quietEnd", "change", "23:30")
        # Chat & Slack: a source on and a poll interval.
        app.section("monitor")
        app.act("settings", "slackEnabled", "toggle", True)
        app.act("settings", "pollInterval", "submit", "45")
        # Google Cloud: a client id and secret, saved in one write.
        app.section("googleCloud")
        app.act(
            "settings",
            "oauthClientId",
            "change",
            "e2e-client.apps.googleusercontent.com",
            keep_ok=True,
        )
        app.act("settings", "oauthClientSecret", "change", "e2e-secret", keep_ok=True)
        saved = app.act("settings", "saveOAuthClient", "tap")
        if not says(saved, "OAuth client saved"):
            raise E2EFailure("Save did not say the OAuth client was saved")
        said.append(
            "settings: quiet hours picked, Slack, poll interval and an OAuth client changed"
        )

        # The island: the extension is HomeSpeaker, installed by definition,
        # so its controls are drawn, and its broadcasting switch saved.
        island = offers_no_quit(app.open("speaker"), "speaker, first page")
        if says(island, "not installed"):
            raise E2EFailure("the island says HomeSpeaker is not installed")
        app.act("speaker", "broadcasting", "toggle", False)
        said.append("speaker: drawn, broadcasting switched off")

        link.send(
            {"jsonrpc": "2.0", "method": "ui/close", "params": {"panel": "speaker"}}
        )
        link.send(
            {"jsonrpc": "2.0", "method": "ui/close", "params": {"panel": "settings"}}
        )
        said.append("shutdown: " + run.shutdown())
        said.extend(app.pages)
    finally:
        link.close()

    # An app from before 3.48 names no features: the quiet hours are the
    # typed field, and a time that is not HH:mm is refused and said.
    older = conf.Link([program], started_in)
    try:
        run = conf.Run(older, manifest, started_in, features=None)
        said.append("an older app: " + run.handshake())
        app = Driver(conf, run)
        general = offers_no_quit(app.open("settings"), "an older app's settings, first page")
        drawn = block(general, "quietEnd")
        if drawn is None or drawn.get("type") != "field":
            raise E2EFailure(
                f"settings: quietEnd is not the typed field for an app without choice: {drawn!r}"
            )
        bad = app.act("settings", "quietEnd", "submit", "soon")
        if not says(bad, "HH:mm"):
            raise E2EFailure("a quiet hour that is not HH:mm was not said on the page")
        older.send(
            {"jsonrpc": "2.0", "method": "ui/close", "params": {"panel": "settings"}}
        )
        said.append("an older app: the typed quiet hour refused; " + run.shutdown())
        said.extend(app.pages)
    finally:
        older.close()

    with open(settings, encoding="utf-8") as handle:
        written = json.load(handle)
    expected = {
        "enabled": False,
        "quiet_hours_enabled": True,
        "quiet_hours_start": "23:00",
        "quiet_hours_end": "23:30",
    }
    for key, value in expected.items():
        if written.get(key) != value:
            raise E2EFailure(
                f"{settings}: {key} is {written.get(key)!r}, not {value!r}"
            )
    if written.get("quiet_hours_end") == "soon":
        raise E2EFailure(f"{settings}: a refused quiet hour was saved")
    monitor = written.get("chat_monitor", {})
    if (
        monitor.get("slack_enabled") is not True
        or monitor.get("poll_interval_seconds") != 45
    ):
        raise E2EFailure(f"{settings}: chat_monitor is {monitor!r}")
    said.append(f"{os.path.relpath(settings, data)}: written as changed")
    with open(secrets, encoding="utf-8") as handle:
        stored = handle.read()
    if "e2e-client.apps.googleusercontent.com" not in stored:
        raise E2EFailure(f"{secrets}: the OAuth client was not saved")
    said.append(f"{os.path.relpath(secrets, data)}: holds the OAuth client")
    return said


if __name__ == "__main__":
    sys.exit(main())
