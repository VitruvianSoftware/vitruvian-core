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

"""Tests for install.py: removing the retired per-user install cleanly from a
temporary HOME, the plain run that changes nothing, and --check against a
throwaway checkout wired like the real one."""

import contextlib
import glob
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from typing import Any, Dict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import install  # noqa: E402
import testlib  # noqa: E402

# The shape of James's real ~/.claude/settings.json hooks (commands shortened).
EXISTING: Dict[str, Any] = {
    "effortLevel": "high",
    "permissions": {"allow": ["Bash"]},
    "hooks": {
        "PermissionRequest": [
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": "'/x/Tools/permission-hook'",
                        "timeout": 150,
                    }
                ]
            }
        ],
        "Stop": [
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": "/h/.claude/response-contract-stop.sh",
                        "timeout": 10,
                    }
                ]
            },
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": '"/x/Tools/stop-hook"',
                        "timeout": 10,
                    }
                ]
            },
        ],
        "UserPromptSubmit": [
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": "/h/.claude/response-contract.sh",
                        "timeout": 5,
                    }
                ]
            }
        ],
    },
    "remoteControlAtStartup": True,
}

# ~/.gemini/config/hooks.json before agent-guard: one named, flat hook.
EXISTING_GEMINI: Dict[str, Any] = {
    "response-contract": {
        "enabled": True,
        "PreInvocation": [
            {
                "type": "command",
                "command": "/h/.gemini/hooks/response-contract.py",
                "timeout": 5,
            }
        ],
    }
}

AGENT_ENV = ("CLAUDECODE", "ANTIGRAVITY_AGENT", "GEMINI_CLI")


def old_install(home: str) -> None:
    """What the retired installer left behind, written exactly as it wrote it."""
    command = "/bin/sh %s/.local/share/agent-guard/hook.sh" % home
    with open(os.path.join(home, ".claude", "settings.json")) as fh:
        settings = json.load(fh)
    pre = settings["hooks"].setdefault("PreToolUse", [])
    pre.append(
        {
            "matcher": install.COMMAND_MATCHER,
            "hooks": [
                {
                    "type": "command",
                    "command": command,
                    "timeout": 10,
                    "onFailure": "block",
                }
            ],
        }
    )
    pre.append(
        {
            "matcher": install.FILE_MATCHER,
            "hooks": [{"type": "command", "command": command, "timeout": 10}],
        }
    )
    with open(os.path.join(home, ".claude", "settings.json"), "w") as fh:
        json.dump(settings, fh, indent=2)
        fh.write("\n")
    gemini = dict(EXISTING_GEMINI)
    gemini["agent-guard"] = install.agy_entry(command)
    with open(os.path.join(home, ".gemini", "config", "hooks.json"), "w") as fh:
        json.dump(gemini, fh, indent=2)
        fh.write("\n")
    idir = os.path.join(home, ".local", "share", "agent-guard")
    os.makedirs(idir)
    for name in ("agent_guard.py", "policy.json", "hook.py", "hook.sh", "VERSION.json"):
        with open(os.path.join(idir, name), "w") as fh:
            fh.write("# old copy\n")


class Base(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp(prefix="agent-guard-home-")
        os.makedirs(os.path.join(self.home, ".claude"))
        os.makedirs(os.path.join(self.home, ".gemini", "config"))
        self.settings = os.path.join(self.home, ".claude", "settings.json")
        self.gemini = os.path.join(self.home, ".gemini", "config", "hooks.json")
        self.idir = os.path.join(self.home, ".local", "share", "agent-guard")
        with open(self.settings, "w") as fh:
            json.dump(EXISTING, fh, indent=2)
            fh.write("\n")
        with open(self.gemini, "w") as fh:
            json.dump(EXISTING_GEMINI, fh, indent=2)
            fh.write("\n")
        self._env = {
            k: v
            for k, v in os.environ.items()
            if k in AGENT_ENV or k.startswith("ANTIGRAVITY_")
        }
        for k in self._env:
            del os.environ[k]

    def tearDown(self):
        os.environ.update(self._env)
        shutil.rmtree(self.home, ignore_errors=True)

    def run_main(self, *args, workspace=""):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            rc = install.main(
                ["--home", self.home, "--workspace", workspace] + list(args)
            )
        return rc, out.getvalue()

    def load(self, path):
        with open(path) as fh:
            return json.load(fh)

    def text(self, path):
        with open(path) as fh:
            return fh.read()


class UninstallTest(Base):
    def test_removes_both_entries_and_the_copy_and_keeps_everything_else(self):
        old_install(self.home)
        rc, out = self.run_main("--uninstall")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.load(self.settings), EXISTING)
        self.assertEqual(self.load(self.gemini), EXISTING_GEMINI)
        self.assertFalse(os.path.exists(self.idir))
        self.assertEqual(len(glob.glob(self.settings + ".agent-guard-*.bak")), 1)
        self.assertEqual(len(glob.glob(self.gemini + ".agent-guard-*.bak")), 1)
        self.assertIn("from the repo", out)

    def test_twice_changes_nothing_more(self):
        old_install(self.home)
        self.run_main("--uninstall")
        before = (self.text(self.settings), self.text(self.gemini))
        rc, out = self.run_main("--uninstall")
        self.assertEqual(rc, 0)
        self.assertIn("no agent-guard hook to remove", out)
        self.assertIn("no per-user copy", out)
        self.assertEqual((self.text(self.settings), self.text(self.gemini)), before)

    def test_keeps_the_log(self):
        old_install(self.home)
        state = os.path.join(self.home, ".local", "state", "agent-guard")
        os.makedirs(state)
        with open(os.path.join(state, "log.jsonl"), "w") as fh:
            fh.write("{}\n")
        self.run_main("--uninstall")
        self.assertTrue(os.path.exists(os.path.join(state, "log.jsonl")))

    def test_dry_run_writes_nothing(self):
        old_install(self.home)
        before = (self.text(self.settings), self.text(self.gemini))
        rc, out = self.run_main("--uninstall", "--dry-run")
        self.assertEqual(rc, 0)
        self.assertIn("would remove", out)
        self.assertIn("+++", out)
        self.assertEqual((self.text(self.settings), self.text(self.gemini)), before)
        self.assertTrue(os.path.isdir(self.idir))

    def test_trims_a_group_shared_with_another_hook(self):
        old_install(self.home)
        s = self.load(self.settings)
        other = {"type": "command", "command": "/x/other-guard.sh"}
        for entry in s["hooks"]["PreToolUse"]:
            entry["hooks"].append(other)
        with open(self.settings, "w") as fh:
            json.dump(s, fh, indent=2)
        g = self.load(self.gemini)
        g["agent-guard"]["PreToolUse"][0]["hooks"].append(other)
        with open(self.gemini, "w") as fh:
            json.dump(g, fh, indent=2)
        self.run_main("--uninstall")
        self.assertEqual(
            [e["hooks"] for e in self.load(self.settings)["hooks"]["PreToolUse"]],
            [[other], [other]],
        )
        self.assertEqual(
            self.load(self.gemini)["agent-guard"]["PreToolUse"][0]["hooks"], [other]
        )

    def test_keeps_the_desktop_apps_json_style(self):
        old_install(self.home)
        s = self.load(self.settings)
        styled = json.dumps(s, indent=2, separators=(",", " : ")).replace("/", "\\/")
        with open(self.settings, "w") as fh:
            fh.write(styled)
        self.run_main("--uninstall")
        text = self.text(self.settings)
        self.assertIn('" : ', text)
        self.assertIn("\\/", text)
        self.assertEqual(json.loads(text), EXISTING)

    def test_a_broken_hooks_json_does_not_block_the_claude_side(self):
        old_install(self.home)
        with open(self.gemini, "w") as fh:
            fh.write("{broken")
        rc, out = self.run_main("--uninstall")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.load(self.settings), EXISTING)
        self.assertEqual(self.text(self.gemini), "{broken")

    def test_refused_inside_an_agent_session(self):
        old_install(self.home)
        for marker in (
            "CLAUDECODE",
            "ANTIGRAVITY_AGENT",
            "GEMINI_CLI",
            "ANTIGRAVITY_LS_ADDRESS",
        ):
            os.environ[marker] = "1"
            try:
                rc, out = self.run_main("--uninstall")
                self.assertEqual(rc, 2, marker)
                self.assertIn(marker, out)
                rc, _ = self.run_main("--uninstall", "--dry-run")
                self.assertEqual(rc, 0, marker)
            finally:
                del os.environ[marker]
        self.assertTrue(os.path.isdir(self.idir))


class PlainRunTest(Base):
    def test_changes_nothing_and_says_where_the_guard_is(self):
        old_install(self.home)
        before = (self.text(self.settings), self.text(self.gemini))
        rc, out = self.run_main()
        self.assertEqual(rc, 0)
        self.assertIn("runs from the repo", out)
        self.assertIn("--uninstall", out)  # the leftover copy is pointed out
        self.assertEqual((self.text(self.settings), self.text(self.gemini)), before)
        self.assertTrue(os.path.isdir(self.idir))

    def test_without_leftovers(self):
        rc, out = self.run_main()
        self.assertEqual(rc, 0)
        self.assertNotIn("--uninstall", out)

    def test_mode_is_gone(self):
        rc, out = self.run_main("--mode", "git-push=warn")
        self.assertEqual(rc, 2)
        self.assertIn("policy.json", out)


class CheckTest(Base):
    def setUp(self):
        super().setUp()
        self.co = testlib.Checkout()

    def tearDown(self):
        self.co.close()
        super().tearDown()

    def test_passes_on_a_checkout_wired_like_the_repo(self):
        rc, out = self.run_main("--check", workspace=self.co.root)
        self.assertEqual(rc, 0, out)
        self.assertIn("origin/main:", out)
        self.assertNotIn("NOTE", out)

    def test_points_out_the_leftover_per_user_copy(self):
        old_install(self.home)
        rc, out = self.run_main("--check", workspace=self.co.root)
        self.assertEqual(rc, 0, out)
        self.assertIn("NOTE: the retired per-user install", out)

    def test_says_when_the_working_copy_answered(self):
        testlib.git(self.co.root, "update-ref", "-d", "refs/remotes/origin/main")
        rc, out = self.run_main("--check", workspace=self.co.root)
        self.assertEqual(rc, 0, out)
        self.assertIn("working-copy (no origin/main", out)

    def test_fails_when_an_entry_is_removed(self):
        path = os.path.join(self.co.root, ".claude", "settings.json")
        s = self.load(path)
        s["hooks"]["PreToolUse"] = s["hooks"]["PreToolUse"][:2]
        with open(path, "w") as fh:
            json.dump(s, fh)
        rc, out = self.run_main("--check", workspace=self.co.root)
        self.assertEqual(rc, 1)
        self.assertIn(".claude/settings.json", out)
        os.remove(os.path.join(self.co.root, ".agents", "hooks.json"))
        rc, out = self.run_main("--check", workspace=self.co.root)
        self.assertIn(".agents/hooks.json is missing", out)

    def test_fails_when_the_launcher_does_not_work(self):
        self.co.write(
            "tools/agent-guard/hook.sh", testlib.launcher_text(["/nonexistent/python3"])
        )
        rc, out = self.run_main("--check", workspace=self.co.root)
        self.assertEqual(rc, 1)
        self.assertIn("no working python3", out)

    def test_fails_when_the_guard_lets_things_through(self):
        self.co.set_policy({"go": "off"}, commit=True)
        rc, out = self.run_main("--check", workspace=self.co.root)
        self.assertEqual(rc, 1)
        self.assertIn("go vet", out)

    def test_needs_a_checkout(self):
        rc, _ = self.run_main("--check")
        self.assertEqual(rc, 2)


if __name__ == "__main__":
    unittest.main()
