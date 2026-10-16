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

"""Verifies the built Vitruvian Remote extension folder and its JSON-RPC protocol end to end.

conformance_test.py <built vitruvian-tool.json> <conformance.py> <vitruvian-tool>
"""

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile

TABS = ["tabGeneral", "tabPairing", "tabNotifications", "tabIntegrations"]
SECONDS = 15


class E2EFailure(Exception):
    """The tool, driven page by page over JSON-RPC, did not do what it should."""


def load(path):
    spec = importlib.util.spec_from_file_location("vitruvian_conformance", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def words(value):
    if isinstance(value, str):
        return [value]
    if isinstance(value, dict):
        return [w for v in value.values() for w in words(v)]
    if isinstance(value, list):
        return [w for v in value for w in words(v)]
    return []


def says(tree, text):
    return any(text in w for b in tree["blocks"] for w in words(b))


def block(tree, block_id):
    return next((b for b in tree["blocks"] if b.get("id") == block_id), None)


class Driver:
    """Plays the Vitruvian host app over JSON-RPC using conformance.py's Run."""

    def __init__(self, conf, run):
        self.conf = conf
        self.run = run
        self.pages = []
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
        if "tree" in result:
            self.run.rendered.pop(panel, None)
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
        shown = self.run.rendered.pop(panel, None) or self.current.get(panel)
        if shown is None or block(shown, block_id) is None:
            raise E2EFailure(f"{where}: the page shown has no such block")
        result = self.ask("ui/event", params, where)
        if "tree" not in result:
            if keep_ok and result.get("keep") is True:
                return None
            raise E2EFailure(f"{where}: answered with no page: {result!r}")
        self.run.rendered.pop(panel, None)
        tree = self.check(result["tree"], where)
        self.current[panel] = tree
        return tree


def main():
    manifest_path, conformance_path, validate_path = sys.argv[1:4]
    built = os.path.dirname(os.path.abspath(manifest_path))
    scratch = tempfile.mkdtemp(dir=os.environ.get("TEST_TMPDIR"))
    folder = os.path.join(scratch, "remote")
    shutil.copytree(built, folder, symlinks=False)

    bundled_agent = os.path.join(folder, "bin", "vitruvian-remote-agent")
    if not os.path.isfile(bundled_agent) or not os.access(bundled_agent, os.X_OK):
        print(f"bundled agent missing or not executable at {bundled_agent}")
        return 1

    home = os.path.join(scratch, "home")
    data_dir = os.path.join(scratch, "data")
    os.makedirs(home)
    os.makedirs(data_dir)

    env = dict(
        os.environ,
        HOME=home,
        CFFIXED_USER_HOME=home,
        REMOTETOOL_HOME=home,
        REMOTETOOL_DATA_FOLDER=data_dir,
        REMOTETOOL_TOOL_FOLDER=folder,
        REMOTETOOL_AGENT_COMMAND="",
        REMOTETOOL_FAKE_STATUS="paired",
        REMOTETOOL_TAILSCALE_ADDRESS="100.124.228.116",
        REMOTETOOL_STANDALONE_INSTALLED="0",
    )

    failed = 0
    for name, command in [
        ("validate", [os.path.abspath(validate_path), "validate", folder]),
        ("conformance", [sys.executable, os.path.abspath(conformance_path), folder]),
    ]:
        done = subprocess.run(
            command, capture_output=True, text=True, timeout=180, check=False, env=env
        )
        print(f"--- {name}: exit {done.returncode}\n{done.stdout}{done.stderr}")
        if done.returncode != 0:
            failed += 1
    if failed:
        print(f"{failed} of 2 checks failed")
        return 1

    conf = load(conformance_path)
    try:
        said = end_to_end_active(conf, folder, scratch)
        said += end_to_end_coexistence(conf, folder, scratch)
    except E2EFailure as failure:
        print(f"--- end to end: NOT OK: {failure}")
        return 1

    print("--- end to end: ok\n" + "\n".join(said))
    print(
        "the built Vitruvian Remote tool validates, passes the conformance script, "
        "and drives its island, all 4 settings tabs, QR pairing, and coexistence end to end"
    )
    return 0


def end_to_end_active(conf, folder, scratch):
    with open(os.path.join(folder, "vitruvian-tool.json"), encoding="utf-8") as handle:
        manifest = json.load(handle)
    program = os.path.join(folder, manifest["runtime"]["exec"])
    home = os.path.join(scratch, "e2e_home")
    data = os.path.join(scratch, "e2e_data")
    os.makedirs(home)
    os.makedirs(data)

    os.environ.update(
        HOME=home,
        CFFIXED_USER_HOME=home,
        REMOTETOOL_HOME=home,
        REMOTETOOL_DATA_FOLDER=data,
        REMOTETOOL_TOOL_FOLDER=folder,
        REMOTETOOL_AGENT_COMMAND="",
        REMOTETOOL_FAKE_STATUS="paired",
        REMOTETOOL_TAILSCALE_ADDRESS="100.124.228.116",
        REMOTETOOL_STANDALONE_INSTALLED="0",
    )
    link = conf.Link([program], data)
    said = []
    try:
        run = conf.Run(link, manifest, data)
        said.append("active handshake: " + run.handshake())
        app = Driver(conf, run)

        # Open island, verify connected phone, and open QR pairing.
        island = app.open("remote")
        if not says(island, "Pixel Fold"):
            raise E2EFailure("island did not show connected Pixel Fold")
        qr_tree = app.act("remote", "islandPairWithQR", "tap")
        if not says(qr_tree, "data:image/png;base64,"):
            raise E2EFailure("islandPairWithQR did not render inline QR PNG data URL")
        said.append("island: rendered connected phone and inline QR code")

        # Open settings and check all 4 tabs.
        app.open("settings")
        for tab in TABS:
            app.act("settings", tab, "tap")
        said.append("settings: " + ", ".join(TABS) + " each drawn")

        # General tab
        app.act("settings", "tabGeneral", "tap")
        app.act("settings", "intervalSeconds", "submit", "5")
        bad_interval = app.act("settings", "intervalSeconds", "submit", "999")
        if not says(bad_interval, "between 1 and 60"):
            raise E2EFailure("out-of-range intervalSeconds was not rejected on page")

        # Pairing & Bridge tab
        app.act("settings", "tabPairing", "tap")
        app.act("settings", "permissionHookToggle", "toggle", True)
        app.act("settings", "permissionWaitSeconds", "submit", "90")

        # Notifications tab
        app.act("settings", "tabNotifications", "tap")
        app.act("settings", "ntfyURL", "submit", "https://ntfy.example.com")
        app.act("settings", "ntfyTopic", "submit", "vitruvian-e2e")
        app.act("settings", "ntfyTokenField", "submit", "tk_e2e_secret")

        # Integrations tab
        app.act("settings", "tabIntegrations", "tap")
        app.act("settings", "kubeContext", "submit", "homelab-e2e")
        app.act("settings", "prometheusURL", "submit", "https://prom.example.com")
        app.act("settings", "prometheusTokenField", "submit", "prom_e2e_secret")
        app.act(
            "settings", "ghExtraRepos", "submit", "VitruvianSoftware/vitruvian-core"
        )

        link.send(
            {"jsonrpc": "2.0", "method": "ui/close", "params": {"panel": "remote"}}
        )
        link.send(
            {"jsonrpc": "2.0", "method": "ui/close", "params": {"panel": "settings"}}
        )
        said.append("active shutdown: " + run.shutdown())
        said.extend(app.pages)
    finally:
        link.close()

    settings_file = os.path.join(data, "settings.json")
    with open(settings_file, encoding="utf-8") as handle:
        written = json.load(handle)
    expected = {
        "interval_seconds": 5,
        "permission_wait_seconds": 90,
        "ntfy_url": "https://ntfy.example.com",
        "ntfy_topic": "vitruvian-e2e",
        "kube_context": "homelab-e2e",
        "prometheus_url": "https://prom.example.com",
        "gh_extra_repos": "VitruvianSoftware/vitruvian-core",
    }
    for key, value in expected.items():
        if written.get(key) != value:
            raise E2EFailure(
                f"settings.json {key} is {written.get(key)!r}, expected {value!r}"
            )

    for secret_name, secret_val in [
        ("ntfy-token", "tk_e2e_secret"),
        ("prometheus-token", "prom_e2e_secret"),
    ]:
        secret_path = os.path.join(data, "config", secret_name)
        with open(secret_path, encoding="utf-8") as handle:
            if handle.read().strip() != secret_val:
                raise E2EFailure(f"{secret_name} was not persisted accurately")

    claude_settings = os.path.join(home, ".claude", "settings.json")
    with open(claude_settings, encoding="utf-8") as handle:
        if "permission-hook --config-dir" not in handle.read():
            raise E2EFailure(
                "~/.claude/settings.json did not receive --config-dir hook"
            )

    said.append(
        "active persistence: settings.json, 0600 tokens, and ~/.claude/settings.json verified"
    )
    return said


def end_to_end_coexistence(conf, folder, scratch):
    with open(os.path.join(folder, "vitruvian-tool.json"), encoding="utf-8") as handle:
        manifest = json.load(handle)
    program = os.path.join(folder, manifest["runtime"]["exec"])
    home = os.path.join(scratch, "coexist_home")
    data = os.path.join(scratch, "coexist_data")
    standalone_cfg = os.path.join(home, ".config", "vitruvian-remote-agent")
    os.makedirs(standalone_cfg)
    os.makedirs(data)

    with open(os.path.join(standalone_cfg, "token"), "w", encoding="utf-8") as handle:
        handle.write("standalone-token-xyz\n")
    with open(os.path.join(standalone_cfg, "paired"), "w", encoding="utf-8") as handle:
        handle.write("2026-10-15T12:00:00Z\n")
    with open(
        os.path.join(standalone_cfg, "settings.json"), "w", encoding="utf-8"
    ) as handle:
        json.dump({"ntfy_url": "https://ntfy.sh", "ntfy_topic": "copied-topic"}, handle)

    os.environ.update(
        HOME=home,
        CFFIXED_USER_HOME=home,
        REMOTETOOL_HOME=home,
        REMOTETOOL_DATA_FOLDER=data,
        REMOTETOOL_TOOL_FOLDER=folder,
        REMOTETOOL_AGENT_COMMAND="",
        REMOTETOOL_FAKE_STATUS="paired",
        REMOTETOOL_TAILSCALE_ADDRESS="100.124.228.116",
        REMOTETOOL_STANDALONE_INSTALLED="1",
    )
    link = conf.Link([program], data)
    said = []
    try:
        run = conf.Run(link, manifest, data)
        said.append("coexistence handshake: " + run.handshake())
        app = Driver(conf, run)

        island = app.open("remote")
        if not says(island, "Choose One Vitruvian Remote"):
            raise E2EFailure("coexistence prompt not shown when both installed")
        app.act("remote", "chooseExtension", "tap")
        active_island = app.act("remote", "confirmUseExtension", "tap")
        if says(active_island, "Choose One Vitruvian Remote"):
            raise E2EFailure("coexistence prompt remained after confirming extension")

        link.send(
            {"jsonrpc": "2.0", "method": "ui/close", "params": {"panel": "remote"}}
        )
        said.append("coexistence shutdown: " + run.shutdown())
    finally:
        link.close()

    choice_path = os.path.join(standalone_cfg, "remote_door.json")
    with open(choice_path, encoding="utf-8") as handle:
        choice = json.load(handle)
    if choice.get("chosen") != "extension":
        raise E2EFailure(
            f"remote_door.json chosen is {choice.get('chosen')!r}, expected 'extension'"
        )
    ext_meta = choice.get("extension") or {}
    if ext_meta.get("program") != program or ext_meta.get("data_folder") != data:
        raise E2EFailure(f"remote_door.json extension metadata mismatch: {ext_meta!r}")

    copied_token_path = os.path.join(data, "config", "token")
    with open(copied_token_path, encoding="utf-8") as handle:
        if handle.read().strip() != "standalone-token-xyz":
            raise E2EFailure(
                "standalone bearer token was not copied to extension config/token"
            )

    said.append(
        "coexistence handoff: remote_door.json and copied bearer token verified"
    )
    return said


if __name__ == "__main__":
    sys.exit(main())
