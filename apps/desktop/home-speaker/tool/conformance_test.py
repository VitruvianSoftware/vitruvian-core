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
which has no `features` and so is given the typed field. The island ends
with a More settings button for this app, which names `ui.open.settings`,
and its tap is answered with `{"open": "settings"}` alone; the older app's
island ends with where the settings are instead, and is never sent `open`.
Nothing is written until the tool has said, on its Files rows, that both
files are in that folder. The island draws its controls because the
extension is installed by definition; no HomeSpeaker program is run. Only
a block on the page the tool last drew is acted on.

Then nothing was written where the app keeps its files: the scratch
home's `.gemini` holds none of the app's settings, history or monitor
status, and the choice file, which both sides share by design, holds only
the extension's own block, naming the scratch folder.

Last, the chat monitor starting, in a second scratch home and data folder:
settings with Slack and Beeper on (as the app's settings copied into the
extension have) and a choice file that picks the extension. The tool starts
its chat monitor on the main actor as it starts. HomeSpeaker 1.19.0 crashed
there, on every start ("Incorrect actor executor assumption"), because its
main thread had left for `dispatchMain()`. Beeper is read from a stand-in
Beeper Desktop this test serves on 127.0.0.1 at a port of its own (never
Beeper's real 23373, which is checked), named by `HOMESPEAKER_BEEPER_URL` as
`http://localhost:<port>`, with a made-up token. The stand-in serves 51
made-up messages 20 a page, as Beeper does, so the program must page by
cursor to reach them all, and must ask for no more than 20 at a time; the
program handles every message (nothing is spoken: broadcasting is off). The
program must still be
running and answering after it has polled more than once, its monitor must
have written that it runs, which Beeper networks it reads, and that it
skips Beeper's Slack (Slack is on and its workspace unknown); the stand-in
must have been asked only with GET and only with the made-up token; and
nothing on its standard error may be a fatal error. That the stand-in was
reached at all shows the program, which has no Info.plist, may make a plain
HTTP request to localhost. Then the same again with the stand-in stopped:
the monitor runs and its status says Beeper Desktop isn't running. Then the
Stop hook, `bin/tool --claude-stop-hook`, in the same folder: it reads the
settings on the main actor, so it must answer `{}`, exit 0 and do so well
before its own eight-second backstop. Broadcasting is off in these
settings and no Slack token exists, so nothing is spoken, and nothing is
fetched but from the stand-in.
"""

import datetime
import http.server
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
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
    try:
        said = monitor_starts(load(conformance), folder, scratch)
    except E2EFailure as failure:
        print(f"--- the chat monitor starting: NOT OK: {failure}")
        return 1
    print("--- the chat monitor starting: ok\n" + "\n".join(said))
    print(
        "the built HomeSpeaker tool validates, passes the conformance script, "
        "draws and saves its pages end to end, keeps to its scratch folder, "
        "and stays up when its chat monitor starts"
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
    if spec is None or spec.loader is None:
        raise E2EFailure(f"{path} cannot be loaded as a module")
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


# The island's last line (Pages.Block.moreSettings, Pages.moreSettings): a
# button for an app that names ui.open.settings, where to look otherwise.
MORE_SETTINGS = "moreSettings"
MORE_SETTINGS_CAPTION = "More settings: Vitruvian Settings › Extensions › HomeSpeaker"

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

        # This app names ui.open.settings: the island ends with a More
        # settings button, and its tap opens the settings panel, with no
        # page (the island stays as it is).
        island = app.current["speaker"]
        last = island["blocks"][-1]
        if last.get("id") != MORE_SETTINGS or last.get("type") != "button":
            raise E2EFailure(
                f"speaker: the last block is not the More settings button: {last!r}"
            )
        opened = app.ask(
            "ui/event",
            {"panel": "speaker", "block": MORE_SETTINGS, "event": "tap"},
            "speaker: tap moreSettings",
        )
        if opened != {"open": "settings"}:
            raise E2EFailure(
                f"speaker: More settings was not answered with open settings alone: {opened!r}"
            )
        said.append("speaker: More settings answered open settings")

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
        general = offers_no_quit(
            app.open("settings"), "an older app's settings, first page"
        )
        drawn = block(general, "quietEnd")
        if drawn is None or drawn.get("type") != "field":
            raise E2EFailure(
                f"settings: quietEnd is not the typed field for an app without choice: {drawn!r}"
            )
        bad = app.act("settings", "quietEnd", "submit", "soon")
        if not says(bad, "HH:mm"):
            raise E2EFailure("a quiet hour that is not HH:mm was not said on the page")
        # It cannot open the settings panel: the island says where they are
        # instead, and a tap on the button's id opens nothing.
        island = app.open("speaker")
        if block(island, MORE_SETTINGS) is not None or not says(
            island, MORE_SETTINGS_CAPTION
        ):
            raise E2EFailure(
                "an older app's island does not end with where the settings are"
            )
        kept = app.ask(
            "ui/event",
            {"panel": "speaker", "block": MORE_SETTINGS, "event": "tap"},
            "an older app's speaker: tap moreSettings",
        )
        if "open" in kept:
            raise E2EFailure(f"an older app was answered with open: {kept!r}")
        older.send(
            {"jsonrpc": "2.0", "method": "ui/close", "params": {"panel": "speaker"}}
        )
        older.send(
            {"jsonrpc": "2.0", "method": "ui/close", "params": {"panel": "settings"}}
        )
        said.append(
            "an older app: the typed quiet hour refused, More settings a caption; "
            + run.shutdown()
        )
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


# What a Swift program says on standard error when it stops on a check.
FATAL = "Fatal error"
# The port Beeper Desktop really listens on. Nothing here may ever reach it.
REAL_BEEPER_PORT = 23373
# A made-up Beeper token, for the stand-in only.
FAKE_BEEPER_TOKEN = (
    "fake-beeper-conformance-token"  # gitleaks:allow (made-up test token)
)
# How long to wait for the monitor to have polled twice (poll interval 5 s).
POLLS_WITHIN_SECONDS = 30
# What the monitor's status says with Beeper Desktop not running.
NOT_RUNNING = "Beeper Desktop isn't running"
# Hand-written fake Beeper accounts: what the status must then say.
BEEPER_ACCOUNTS = [
    {
        "accountID": "local-whatsapp_ba_FAKE",
        "bridge": {"id": "local-whatsapp", "type": "whatsapp", "provider": "local"},
        "network": "WhatsApp",
        "user": {"id": "@me-wa:fake.test", "isSelf": True, "fullName": "Me"},
    },
    {
        "accountID": "local-signal_FAKE",
        "network": "Signal",
        "user": {"id": "@me-signal:fake.test"},
    },
    {
        "accountID": "slackgo.TFAKE-UFAKE",
        "network": "Slack",
        "user": {"id": "@me-slack:fake.test"},
    },
    {
        "accountID": "gmessages.someone@example.test/0",
        "bridge": {"type": "gmessages"},
        "network": "Google Messages",
        "user": {"id": "@me-sms:fake.test"},
    },
]
BEEPER_READS = ["Google Messages", "Signal", "WhatsApp"]
BEEPER_SKIPS = ["Slack"]
# The most messages a page holds, as Beeper serves them.
BEEPER_PAGE = 20
# The chats the made-up messages are in.
BEEPER_CHATS = {
    "wa-dm": {"id": "wa-dm", "type": "single", "title": "Alice", "network": "WhatsApp"},
    "sig-family": {
        "id": "sig-family",
        "type": "group",
        "title": "Family",
        "network": "Signal",
    },
    "slack-dm": {
        "id": "slack-dm",
        "type": "single",
        "title": "Dee",
        "network": "Slack",
    },
}


def beeper_messages(start):
    """Made-up messages in the second after `start` (the first search's
    `dateAfter`, which is when the monitor started): one WhatsApp DM, older
    than a page of Slack (skipped, since Slack is on) and a page of group
    chat without a mention, so it is only reached by paging."""

    def message(mid, chat, account, sender, seconds_after, text):
        stamp = start + datetime.timedelta(seconds=seconds_after)
        return {
            "id": mid,
            "chatID": chat,
            "accountID": account,
            "senderID": f"@{sender.lower()}:fake.test",
            "senderName": sender,
            "timestamp": stamp.strftime("%Y-%m-%dT%H:%M:%S.")
            + f"{stamp.microsecond // 1000:03d}Z",
            "type": "TEXT",
            "text": text,
            "isSender": False,
            "isHidden": False,
            "isDeleted": False,
            "mentions": None,
        }

    out = [
        message(
            "dm", "wa-dm", "local-whatsapp_ba_FAKE", "Alice", 0.01, "behind the others"
        )
    ]
    out += [
        message(
            f"s{n}",
            "slack-dm",
            "slackgo.TFAKE-UFAKE",
            "Dee",
            0.5 + n / 100,
            f"busy {n}",
        )
        for n in range(25)
    ]
    out += [
        message(
            f"g{n}",
            "sig-family",
            "local-signal_FAKE",
            "Bob",
            0.2 + n / 100,
            f"chat {n}",
        )
        for n in range(25)
    ]
    return out


class StandInBeeper:
    """Beeper Desktop's API, as far as HomeSpeaker asks it, served on
    127.0.0.1 at a free port, recording every request: its method, path
    and token. Anything but GET is refused with 405 and recorded, so a
    check can fail on it."""

    def __init__(self):
        self.requests = []
        self.lock = threading.Lock()
        # Made at the first search, after the monitor started.
        self.messages = None
        stand_in = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, format, *args):  # noqa: A002 (the base class names it)
                pass

            def answer(self):
                auth = self.headers.get("Authorization", "")
                path, _, query_text = self.path.partition("?")
                query = dict(urllib.parse.parse_qsl(query_text))
                with stand_in.lock:
                    stand_in.requests.append((self.command, path, auth, query))
                if self.command != "GET":
                    return self.send(405, {"message": "method not allowed"})
                if auth != f"Bearer {FAKE_BEEPER_TOKEN}":
                    return self.send(
                        401, {"message": "Unauthorized", "code": "unauthorized"}
                    )
                if path == "/v1/accounts":
                    return self.send(200, BEEPER_ACCOUNTS)
                if path == "/v1/messages/search":
                    return self.send(*stand_in.page(query))
                return self.send(404, {"message": "not found"})

            def send(self, status, body):
                data = json.dumps(body).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(data)

            do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_HEAD = do_OPTIONS = (
                answer
            )

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.port = self.server.server_address[1]
        if self.port == REAL_BEEPER_PORT:
            self.server.server_close()
            raise E2EFailure(
                f"the stand-in Beeper got port {REAL_BEEPER_PORT}, the real Beeper's"
            )
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def page(self, query):
        """One page of the messages after `dateAfter`, newest first, at
        most `limit` (no more than 20), with `hasMore` and cursors: offsets
        into that order, carried on with `direction=before`."""
        try:
            limit = int(query.get("limit", BEEPER_PAGE))
        except ValueError:
            limit = 0
        if not 1 <= limit <= BEEPER_PAGE:
            return 400, {"message": f"limit must be 1 to {BEEPER_PAGE}"}
        with self.lock:
            if self.messages is None:
                start = datetime.datetime.strptime(
                    query.get("dateAfter", ""), "%Y-%m-%dT%H:%M:%S.%fZ"
                ).replace(tzinfo=datetime.timezone.utc)
                self.messages = beeper_messages(start)
            messages = list(self.messages)
        after = query.get("dateAfter", "")
        # ISO 8601 in UTC with milliseconds sorts as text.
        matching = sorted(
            (m for m in messages if m["timestamp"] > after),
            key=lambda m: m["timestamp"],
            reverse=True,
        )
        offset = 0
        if "cursor" in query:
            if query.get("direction") != "before" or not query["cursor"].startswith(
                "c"
            ):
                return 400, {"message": "bad cursor"}
            offset = int(query["cursor"][1:])
        items = matching[offset : offset + limit]
        end = offset + len(items)
        return 200, {
            "items": items,
            "hasMore": end < len(matching),
            "oldestCursor": f"c{end}",
            "newestCursor": f"c{offset}",
            "chats": BEEPER_CHATS,
        }

    @property
    def url(self):
        # localhost, as HomeSpeaker writes Beeper's own address: App
        # Transport Security allows plain HTTP to it.
        return f"http://localhost:{self.port}"

    def seen(self):
        with self.lock:
            return list(self.requests)

    def searches(self):
        return [r for r in self.seen() if r[1] == "/v1/messages/search"]

    def polls(self):
        """The searches that began a poll: no cursor."""
        return [r for r in self.searches() if "cursor" not in r[3]]

    def stop(self):
        self.server.shutdown()
        self.server.server_close()


# How long the tool runs after the handshake before it is asked again: the
# monitor is started on the main queue, at once, as the tool starts.
SETTLE_SECONDS = 3
# The Stop hook's own backstop (HomeSpeakerCommandLine.timeLimit): a run
# that takes this long timed out, though it still printed `{}` and exit 0.
HOOK_BACKSTOP_SECONDS = 8


def monitor_starts(conf, folder, scratch):
    """The tool starts its chat monitor and stays up; then the Stop hook
    answers. In a home and data folder of their own, so the checks above
    on the first home's choice file are not disturbed. Returns what was
    done, a line each."""
    base = os.path.join(scratch, "monitor")
    home = os.path.join(base, "home")
    data = os.path.join(base, "data")
    gemini = os.path.join(home, ".gemini")
    os.makedirs(gemini)
    os.makedirs(data)
    # SWIFT_IS_CURRENT_EXECUTOR_LEGACY_MODE_OVERRIDE: the release's program
    # (SwiftPM, macOS 14 and up) records SDK 14, so the Swift runtime checks
    # `MainActor.assumeIsolated` by thread, and traps off the main thread.
    # Bazel's records this Mac's SDK, so the runtime checks by queue, which
    # a worker thread draining the main queue passes. "legacy" makes this
    # program check as the release's does; without it, this run could not
    # catch the 1.19.0 crash.
    beeper = StandInBeeper()
    env = dict(
        os.environ,
        HOME=home,
        CFFIXED_USER_HOME=home,
        HOMESPEAKER_DATA_FOLDER=data,
        HOMESPEAKER_PROGRAM="",
        HOMESPEAKER_MESSAGE_PREFIX=f"test.{uuid.uuid4()}.homespeaker",
        SWIFT_IS_CURRENT_EXECUTOR_LEGACY_MODE_OVERRIDE="legacy",
        HOMESPEAKER_BEEPER_URL=beeper.url,
    )
    if f":{REAL_BEEPER_PORT}" in env["HOMESPEAKER_BEEPER_URL"]:
        raise E2EFailure("HOMESPEAKER_BEEPER_URL names the real Beeper's port")
    # Slack and Beeper on, as in settings copied from the app, polling every
    # five seconds; broadcasting off, no speaker. The first four keys are
    # the ones a settings file must have.
    with open(os.path.join(data, "settings.json"), "w", encoding="utf-8") as handle:
        json.dump(
            {
                "enabled": False,
                "default_target": "",
                "structure_id": "",
                "targets": {},
                "chat_monitor": {
                    "slack_enabled": True,
                    "beeper_enabled": True,
                    "poll_interval_seconds": 5,
                },
            },
            handle,
        )
    # The made-up Beeper token, and no Slack token.
    secrets = os.path.join(data, "secrets.json")
    with open(secrets, "w", encoding="utf-8") as handle:
        json.dump({"beeperToken": FAKE_BEEPER_TOKEN}, handle)
    os.chmod(secrets, 0o600)
    # The person picked the extension, an hour ago: long enough that the
    # tool does not wait for a HomeSpeaker app running on this Mac to go
    # quiet (HomeSpeakerTool.otherStopsWithin) before its monitor starts.
    with open(os.path.join(gemini, DOOR_FILE), "w", encoding="utf-8") as handle:
        json.dump(
            {
                "version": 1,
                "chosen": "extension",
                "chosen_at": time.strftime(
                    "%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 3600)
                ),
                "chosen_by": "conformance test",
            },
            handle,
        )
    with open(os.path.join(folder, "vitruvian-tool.json"), encoding="utf-8") as handle:
        manifest = json.load(handle)
    program = os.path.join(folder, manifest["runtime"]["exec"])
    status = os.path.join(data, "speaker_monitor_status.json")
    errors = os.path.join(base, "stderr.txt")
    said = []

    # The kit's link starts the program with this process's environment,
    # and leaves its standard error to this process's: a shell in front
    # sends it to a file instead, then becomes the program.
    os.environ.update(env)
    try:
        said += run_with_monitor(
            conf,
            manifest,
            program,
            errors,
            status,
            "with the stand-in Beeper",
            lambda: len(beeper.polls()) >= 2,
            lambda: (
                f"the monitor never polled the stand-in Beeper twice in {POLLS_WITHIN_SECONDS} s; "
                f"it was asked {[(m, p) for m, p, _, _ in beeper.seen()]!r}"
            ),
        )
        with open(status, encoding="utf-8") as handle:
            written = json.load(handle)
        if written.get("is_running") is not True:
            raise E2EFailure(f"the monitor's status does not say it runs: {written!r}")
        if written.get("beeper_networks") != BEEPER_READS:
            raise E2EFailure(
                f"the monitor reads Beeper's {written.get('beeper_networks')!r}, not {BEEPER_READS!r}"
            )
        if written.get("beeper_skipped_networks") != BEEPER_SKIPS:
            raise E2EFailure(
                f"the monitor skips Beeper's {written.get('beeper_skipped_networks')!r}, not {BEEPER_SKIPS!r}"
            )
        asked = beeper.seen()
        wrong = [
            r for r in asked if r[0] != "GET" or r[2] != f"Bearer {FAKE_BEEPER_TOKEN}"
        ]
        if wrong:
            raise E2EFailure(
                "the stand-in Beeper was asked with another method or without the made-up "
                f"token: {[(m, p) for m, p, _, _ in wrong]!r}"
            )
        searches = beeper.searches()
        if any(q.get("limit") != str(BEEPER_PAGE) for _, _, _, q in searches):
            raise E2EFailure(
                f"a search asked for more than {BEEPER_PAGE}: {[q for _, _, _, q in searches]!r}"
            )
        # 51 messages, 20 a page: each poll reads three pages.
        paged = [q for _, _, _, q in searches if "cursor" in q]
        if len(paged) < 2:
            raise E2EFailure(
                "the monitor did not page through the stand-in's 51 messages: "
                f"{[q for _, _, _, q in searches]!r}"
            )
        said.append(
            f"the stand-in Beeper was asked {len(asked)} times, every time a GET with the "
            f"made-up token: {sorted({p for _, p, _, _ in asked})}; {len(beeper.polls())} polls, "
            f"{len(paged)} further pages by cursor; plain HTTP to localhost is allowed"
        )
    finally:
        beeper.stop()

    # Beeper Desktop not running: the monitor runs, and says so.
    def says_not_running():
        try:
            with open(status, encoding="utf-8") as handle:
                return NOT_RUNNING in (json.load(handle).get("last_error") or "")
        except (OSError, ValueError):
            return False

    os.remove(status)
    said += run_with_monitor(
        conf,
        manifest,
        program,
        errors,
        status,
        "with Beeper not running",
        says_not_running,
        lambda: (
            f"the monitor's status never said {NOT_RUNNING!r} with the stand-in stopped"
        ),
    )
    with open(status, encoding="utf-8") as handle:
        written = json.load(handle)
    if written.get("is_running") is not True:
        raise E2EFailure(
            f"with Beeper not running, the monitor did not run: {written!r}"
        )
    said.append("with Beeper not running: " + written.get("last_error"))

    # The Stop hook, on the same settings: its own process, which reads them
    # on the main actor, answers `{}` and exits 0.
    started_in = tempfile.mkdtemp(dir=os.environ.get("TEST_TMPDIR"))
    transcript = os.path.join(base, "transcript.jsonl")
    with open(transcript, "w", encoding="utf-8") as handle:
        handle.write(
            json.dumps(
                {
                    "type": "assistant",
                    "message": {
                        "role": "assistant",
                        "content": [
                            {"type": "text", "text": f"test {uuid.uuid4()}: done."}
                        ],
                    },
                }
            )
            + "\n"
        )
    started = time.monotonic()
    done = subprocess.run(
        [program, "--claude-stop-hook"],
        input=json.dumps({"transcript_path": transcript}),
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
        env=env,
        cwd=started_in,
    )
    took = time.monotonic() - started
    if done.returncode != 0 or done.stdout.strip() != "{}" or FATAL in done.stderr:
        raise E2EFailure(
            f"--claude-stop-hook exited {done.returncode}: {done.stdout!r} {done.stderr!r}"
        )
    if took >= HOOK_BACKSTOP_SECONDS - 1:
        raise E2EFailure(
            f"--claude-stop-hook took {took:.1f} s: it ran into its "
            f"{HOOK_BACKSTOP_SECONDS} s backstop instead of finishing"
        )
    said.append(f"--claude-stop-hook: {{}} and exit 0 in {took:.1f} s")
    return said


def run_with_monitor(conf, manifest, program, errors, status, name, until, never):
    """Starts the program with the chat monitor on, waits for `until`
    (`never()` says why it did not come), checks it is still running and
    answering, and shuts it down. Its standard error goes to `errors`,
    which must hold no fatal error."""
    started_in = tempfile.mkdtemp(dir=os.environ.get("TEST_TMPDIR"))
    said = []
    link = conf.Link(
        ["/bin/sh", "-c", 'exec "$0" 2>>"$1"', program, errors], started_in
    )
    try:
        run = conf.Run(link, manifest, started_in)
        try:
            said.append(f"{name}: handshake: " + run.handshake())
        except conf.Failure as failure:
            raise E2EFailure(
                f"{name}: handshake: {failure}; {stderr_of(errors)}"
            ) from None
        started = time.monotonic()
        while not until():
            if link.process.poll() is not None:
                raise E2EFailure(
                    f"{name}: the tool ended by itself, status {link.process.returncode}, "
                    f"{time.monotonic() - started:.0f} s after it started with the chat monitor on; "
                    + stderr_of(errors)
                )
            if time.monotonic() - started > POLLS_WITHIN_SECONDS:
                raise E2EFailure(f"{name}: {never()}; " + stderr_of(errors))
            time.sleep(0.25)
        waited = time.monotonic() - started
        time.sleep(SETTLE_SECONDS)
        if link.process.poll() is not None:
            raise E2EFailure(
                f"{name}: the tool ended by itself, status {link.process.returncode}; "
                + stderr_of(errors)
            )
        app = Driver(conf, run)
        try:
            app.open("settings")
        except E2EFailure as failure:
            raise E2EFailure(f"{name}: {failure}; {stderr_of(errors)}") from None
        said.append(
            f"{name}: still running and answering {waited + SETTLE_SECONDS:.0f} s after it started"
        )
        if not os.path.exists(status):
            raise E2EFailure(
                f"{name}: {status} was not written: the chat monitor never started, "
                "so this run proves nothing; " + stderr_of(errors)
            )
        with open(status, encoding="utf-8") as handle:
            said.append(
                f"{name}: the monitor's status: "
                + json.dumps(json.load(handle), sort_keys=True)
            )
        link.send(
            {"jsonrpc": "2.0", "method": "ui/close", "params": {"panel": "settings"}}
        )
        try:
            said.append(f"{name}: shutdown: " + run.shutdown())
        except conf.Failure as failure:
            raise E2EFailure(
                f"{name}: shutdown: {failure}; {stderr_of(errors)}"
            ) from None
    finally:
        link.close()
    if FATAL in stderr_of(errors):
        raise E2EFailure(f"{name}: " + stderr_of(errors))
    return said


def stderr_of(path):
    """What the program wrote on standard error, for a failure's message."""
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read().strip()
    except OSError:
        return "no standard error was kept"
    return f"its standard error: {text!r}" if text else "nothing on its standard error"


if __name__ == "__main__":
    sys.exit(main())
