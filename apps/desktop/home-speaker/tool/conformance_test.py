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
the `sayClipboard` command (answered with a refusal: as far as the program
is allowed to see, HomeSpeaker is not installed), an unknown command, the
island panel opened and its page read, the refusals, and a clean exit. The
program runs under a home of its own with no settings file in it, and
`HOMESPEAKER_PROGRAM` set and empty keeps it off the HomeSpeaker Launch
Services would find on this Mac, so it speaks on nothing of this Mac's.

Then it plays the app itself, over the same JSON-RPC on stdin and stdout,
with the conformance script's own link and checks (imported, not copied):
the island and each of the five settings sections are opened, every page
is held to the protocol's limits (`is_tree`: the most blocks, the most
bytes, the choice rules), switches and fields are changed, and the
settings file and the secrets file are read back from the home of its
own. Nothing is written until the tool has said, on its Files rows, that
both files are in that home. There, `HOMESPEAKER_PROGRAM` names a stand-in
for HomeSpeaker's program, a shell script that never speaks, so the island
draws the controls an installed HomeSpeaker gets. Only a block on the page
the tool last drew is acted on.
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

# HomeSpeaker's program, as far as the tool can tell: it answers the volume
# with no speaker, the login item as off, and refuses everything else. It
# speaks on nothing and reaches nothing.
STAND_IN = """#!/bin/sh
case "$1" in
  --volume|--set-volume|--mute|--unmute)
    echo '{"available": false, "reason": "the end-to-end stand-in has no speaker"}'
    exit 1 ;;
  --login-item)
    echo "login item: disabled" ;;
  *)
    echo "error: the end-to-end stand-in does nothing" >&2
    exit 1 ;;
esac
"""


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
    # A home of its own: the tool reads ~/.gemini/speaker_broadcast.json
    # and looks in ~/Applications, and with this Mac's home it would find
    # both. CFFIXED_USER_HOME is what NSHomeDirectory() reads. Launch
    # Services would still know this Mac's HomeSpeaker by its bundle id,
    # whatever the home: HOMESPEAKER_PROGRAM, set and empty, keeps the tool
    # off it, so nothing here can speak.
    # HOMESPEAKER_MESSAGE_PREFIX: the program listens and posts under a
    # prefix of this run's own, so a HomeSpeaker extension running on this
    # Mac hears nothing of it.
    env = dict(
        os.environ,
        HOME=home,
        CFFIXED_USER_HOME=home,
        HOMESPEAKER_PROGRAM="",
        HOMESPEAKER_MESSAGE_PREFIX=f"test.{uuid.uuid4()}.homespeaker",
    )
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
        # The command must have been refused, not run: a run means the
        # program found a HomeSpeaker, which no test may drive.
        if name == "conformance" and "sayClipboard: refused" not in done.stdout:
            print(
                "the sayClipboard command was not refused: the program found a HomeSpeaker to drive"
            )
            failed += 1
    if failed:
        print(f"{failed} of 2 checks failed")
        return 1
    try:
        said = end_to_end(load(conformance), folder, home, env)
    except E2EFailure as failure:
        print(f"--- end to end: NOT OK: {failure}")
        return 1
    print("--- end to end: ok\n" + "\n".join(said))
    print(
        "the built HomeSpeaker tool validates, passes the conformance script, "
        "and draws and saves its pages end to end"
    )
    return 0


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


def end_to_end(conf, folder, home, env):
    """Opens every page the app can show and changes what it can save,
    under `home`. Returns what was done, a line each."""
    with open(os.path.join(folder, "vitruvian-tool.json"), encoding="utf-8") as handle:
        manifest = json.load(handle)
    program = os.path.join(folder, manifest["runtime"]["exec"])
    gemini = os.path.join(home, ".gemini")
    settings = os.path.join(gemini, "speaker_broadcast.json")
    data = tempfile.mkdtemp(dir=os.environ.get("TEST_TMPDIR"))
    stand_in = os.path.join(data, "HomeSpeaker")
    with open(stand_in, "w", encoding="utf-8") as handle:
        handle.write(STAND_IN)
    os.chmod(stand_in, 0o755)
    # The kit's link starts the program with this process's environment.
    os.environ.update(env, HOMESPEAKER_PROGRAM=stand_in)
    link = conf.Link([program], data)
    said = []
    try:
        run = conf.Run(link, manifest, data)
        said.append("handshake: " + run.handshake())
        app = Driver(conf, run)

        # Before anything is written: the tool must be using this home.
        app.open("settings")
        cloud = app.section("googleCloud")
        if not says(cloud, settings):
            raise E2EFailure(
                f"Files does not name {settings}: the tool is not using the test's "
                "home, and nothing may be written"
            )
        secrets = next(
            (
                w
                for b in cloud["blocks"]
                if "Secrets" in words(b)
                for w in words(b)
                if w.startswith(home)
            ),
            None,
        )
        if secrets is None:
            raise E2EFailure("Files does not name a secrets file in the test's home")

        for name in SECTIONS:
            app.section(name)
        said.append("settings: " + ", ".join(SECTIONS) + " each drawn")

        # General: a switch and a field are saved; a bad time is said.
        app.section("general")
        app.act("settings", "quiet", "toggle", True)
        app.act("settings", "quietStart", "submit", "23:15")
        bad = app.act("settings", "quietEnd", "submit", "soon")
        if not says(bad, "HH:mm"):
            raise E2EFailure("a quiet hour that is not HH:mm was not said on the page")
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
            "settings: quiet hours, Slack, poll interval and an OAuth client changed"
        )

        # The island: drawn as an installed HomeSpeaker's, and its
        # broadcasting switch saved.
        island = app.open("speaker")
        if says(island, "not installed"):
            raise E2EFailure("the island did not find the stand-in HomeSpeaker")
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

    with open(settings, encoding="utf-8") as handle:
        written = json.load(handle)
    expected = {
        "enabled": False,
        "quiet_hours_enabled": True,
        "quiet_hours_start": "23:15",
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
    said.append(f"{os.path.relpath(settings, home)}: written as changed")
    with open(secrets, encoding="utf-8") as handle:
        stored = handle.read()
    if "e2e-client.apps.googleusercontent.com" not in stored:
        raise E2EFailure(f"{secrets}: the OAuth client was not saved")
    said.append(f"{os.path.relpath(secrets, home)}: holds the OAuth client")
    return said


if __name__ == "__main__":
    sys.exit(main())
