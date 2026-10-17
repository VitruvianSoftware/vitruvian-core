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

"""Tests for install.py against a temporary HOME: the per-user backstop (which
runs the main checkout's hook.sh) and its migration from the old copied
install, --uninstall, and --check against a throwaway checkout wired like the
real one."""

import contextlib
import glob
import io
import json
import os
import shutil
import subprocess
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
        self.assertIn("sessions started anywhere else are not", out)

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


class InstallTest(Base):
    """The thin backstop: user entries that run the MAIN checkout's hook.sh."""

    def setUp(self):
        super().setUp()
        self.co = testlib.Checkout()
        self.command = install.backstop_command(self.co.root)

    def tearDown(self):
        self.co.close()
        super().tearDown()

    def ours(self):
        s = self.load(self.settings)
        return [
            e
            for e in s.get("hooks", {}).get("PreToolUse", [])
            if any(install._is_ours(h) for h in e.get("hooks", []))
        ]

    def test_writes_both_entries_pointing_at_the_main_checkout(self):
        rc, out = self.run_main(workspace=self.co.root)
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.ours(), install.claude_entries(self.command))
        self.assertEqual(install.backstop_main(self.command), self.co.root)
        self.assertEqual(
            self.load(self.gemini)["agent-guard"], install.agy_entry(self.command)
        )
        # Everything else is kept.
        s = self.load(self.settings)
        for k, v in EXISTING.items():
            if k != "hooks":
                self.assertEqual(s[k], v)
        for event, entries in EXISTING["hooks"].items():
            self.assertEqual(s["hooks"][event], entries)
        self.assertEqual(
            self.load(self.gemini)["response-contract"],
            EXISTING_GEMINI["response-contract"],
        )
        self.assertIn("reinstall only if you move", out)

    def test_migrates_the_old_copy(self):
        old_install(self.home)
        rc, out = self.run_main(workspace=self.co.root)
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.ours(), install.claude_entries(self.command))
        self.assertNotIn(".local/share/agent-guard", self.text(self.settings))
        self.assertNotIn(".local/share/agent-guard", self.text(self.gemini))
        self.assertFalse(os.path.exists(self.idir))
        self.assertEqual(len(glob.glob(self.settings + ".agent-guard-*.bak")), 1)
        self.assertIn("removed the old per-user copy", out)

    def test_from_a_worktree_it_still_points_at_the_main_checkout(self):
        wt = os.path.join(self.co.tmp, "wt")
        testlib.git(self.co.root, "worktree", "add", "-q", "--detach", wt)
        rc, out = self.run_main(workspace=wt)
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.ours(), install.claude_entries(self.command))

    def test_a_write_error_puts_both_files_back(self):
        old_install(self.home)
        before = (self.text(self.settings), self.text(self.gemini))
        real = install.write_atomic

        def failing(path, text):
            if path == self.gemini and text != before[1]:
                raise OSError("disk full")
            real(path, text)

        install.write_atomic = failing
        try:
            rc, out = self.run_main(workspace=self.co.root)
        finally:
            install.write_atomic = real
        self.assertEqual(rc, 4, out)
        self.assertIn("disk full", out)
        self.assertEqual((self.text(self.settings), self.text(self.gemini)), before)
        self.assertTrue(os.path.isdir(self.idir))

    def backstop(self, payload):
        """Run the backstop's command the way the agents do."""
        r = subprocess.run(
            self.command,
            shell=True,
            input=json.dumps(payload).encode(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=self.home,
            env=dict(os.environ, HOME=self.home),
            timeout=60,
        )
        return r.returncode, r.stdout.decode().strip(), r.stderr.decode()

    def test_backstop_with_its_launcher_runs_the_guard(self):
        rc, out, err = self.backstop(testlib.claude("git stash", self.co.root))
        self.assertEqual((rc, testlib.decision(out)), (0, "deny"), err)

    def test_backstop_without_its_launcher_refuses_only_vitruvian_core(self):
        os.remove(os.path.join(self.co.root, "tools/agent-guard/hook.sh"))
        wt = self.co.root + "-worktrees"
        for payload in (
            testlib.claude("ls", self.co.root),
            testlib.claude("ls", os.path.join(self.co.root, "apps")),
            testlib.claude("ls", os.path.join(wt, "feat-x")),
            testlib.claude("cat %s/README.md" % self.co.root, self.home),
        ):
            rc, out, err = self.backstop(payload)
            # Claude Code: exit 2 refuses the call, with stderr as the reason.
            self.assertEqual((rc, out), (2, ""), payload)
            self.assertIn("launcher is missing from %s" % self.co.root, err)
            self.assertIn("James must reinstall", err)
        rc, out, _err = self.backstop(
            testlib.agy("ls", os.path.join(self.co.root, "apps"))
        )
        self.assertEqual(rc, 0)
        self.assertEqual(json.loads(out)["decision"], "deny")
        self.assertIn("launcher is missing", json.loads(out)["reason"])
        # Anything else, including a sibling folder with a longer name, goes through.
        for payload in (
            testlib.claude("ls", self.home),
            testlib.claude("ls", self.co.root + "-other"),
            testlib.agy("ls", self.home),
        ):
            rc, out, err = self.backstop(payload)
            self.assertEqual((rc, out), (0, ""), payload)
            self.assertIn("allowing this call", err)

    def test_idempotent(self):
        self.run_main(workspace=self.co.root)
        before = (self.text(self.settings), self.text(self.gemini))
        rc, out = self.run_main(workspace=self.co.root)
        self.assertEqual(rc, 0)
        self.assertIn("already installed", out)
        self.assertEqual((self.text(self.settings), self.text(self.gemini)), before)
        self.assertEqual(len(glob.glob(self.settings + ".agent-guard-*.bak")), 1)

    def test_dry_run_writes_nothing(self):
        old_install(self.home)
        before = (self.text(self.settings), self.text(self.gemini))
        rc, out = self.run_main("--dry-run", workspace=self.co.root)
        self.assertEqual(rc, 0)
        self.assertIn("+++", out)
        self.assertIn("would remove the old per-user copy", out)
        self.assertEqual((self.text(self.settings), self.text(self.gemini)), before)
        self.assertTrue(os.path.isdir(self.idir))

    def test_a_failing_self_test_puts_everything_back(self):
        old_install(self.home)
        self.co.write(
            "tools/agent-guard/hook.sh", testlib.launcher_text(["/nonexistent/python3"])
        )
        before = (self.text(self.settings), self.text(self.gemini))
        rc, out = self.run_main(workspace=self.co.root)
        self.assertEqual(rc, 4, out)
        self.assertIn("no working python3", out)
        self.assertEqual((self.text(self.settings), self.text(self.gemini)), before)
        self.assertTrue(os.path.isdir(self.idir))

    def test_antigravity_absent_is_left_alone(self):
        shutil.rmtree(os.path.join(self.home, ".gemini"))
        rc, out = self.run_main(workspace=self.co.root)
        self.assertEqual(rc, 0, out)
        self.assertFalse(os.path.exists(os.path.join(self.home, ".gemini")))
        self.assertEqual(self.ours(), install.claude_entries(self.command))

    def test_a_main_checkout_without_the_launcher_is_refused(self):
        os.remove(os.path.join(self.co.root, "tools/agent-guard/hook.sh"))
        with self.assertRaises(SystemExit) as cm:
            self.run_main(workspace=self.co.root)
        self.assertIn("pull main there first", str(cm.exception))

    def test_an_agent_may_not_aim_it_with_home_or_workspace(self):
        os.environ["CLAUDECODE"] = "1"
        try:
            rc, out = self.run_main(workspace=self.co.root)
            self.assertEqual(rc, 2)
            self.assertIn("--home/--workspace", out)
            self.assertIn("CLAUDECODE", out)
            rc, _ = self.run_main("--dry-run", workspace=self.co.root)
            self.assertEqual(rc, 0)
        finally:
            del os.environ["CLAUDECODE"]
        self.assertEqual(self.ours(), [])

    def test_uninstall_removes_the_backstop(self):
        self.run_main(workspace=self.co.root)
        rc, out = self.run_main("--uninstall")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.load(self.settings), EXISTING)
        self.assertEqual(self.load(self.gemini), EXISTING_GEMINI)
        self.assertIn("sessions started anywhere else are not", out)

    def test_mode_is_gone(self):
        rc, out = self.run_main("--mode", "git-push=warn")
        self.assertEqual(rc, 2)
        self.assertIn("policy.json", out)


ORIGIN = "https://github.com/VitruvianSoftware/vitruvian-core.git"


class AgentInstallTest(Base):
    """An agent's install: the real HOME (here a temp one) and the checkout
    `bazel run` ran in, never --home/--workspace; checked, then logged."""

    def setUp(self):
        super().setUp()
        self.co = testlib.Checkout()
        testlib.git(self.co.root, "remote", "add", "origin", ORIGIN)
        self.command = install.backstop_command(self.co.root)
        self._saved = {
            k: os.environ.get(k)
            for k in ("HOME", "BUILD_WORKSPACE_DIRECTORY", "CLAUDE_CODE_SESSION_ID")
        }
        os.environ.update(
            HOME=self.home,
            BUILD_WORKSPACE_DIRECTORY=self.co.root,
            CLAUDE_CODE_SESSION_ID="session-under-test",
            CLAUDECODE="1",
        )

    def tearDown(self):
        os.environ.pop("CLAUDECODE", None)
        for k, v in self._saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.co.close()
        super().tearDown()

    def agent(self, *args, workspace=None):
        if workspace is not None:
            os.environ["BUILD_WORKSPACE_DIRECTORY"] = workspace
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            rc = install.main(list(args))
        return rc, out.getvalue()

    def ours(self):
        s = self.load(self.settings)
        return [
            e
            for e in s.get("hooks", {}).get("PreToolUse", [])
            if any(install._is_ours(h) for h in e.get("hooks", []))
        ]

    def installs(self):
        """The agent-install lines in agent-guard's log."""
        path = os.path.join(self.home, ".local", "state", "agent-guard", "log.jsonl")
        if not os.path.exists(path):
            return []
        with open(path) as fh:
            lines = [json.loads(line) for line in fh]
        return [r for r in lines if r.get("event") == "agent-install"]

    def assert_refused(self, rc, out, needle):
        self.assertEqual(rc, 2, out)
        self.assertIn(needle, out)
        self.assertIn("CLAUDECODE", out)
        self.assertEqual(self.ours(), [])
        self.assertEqual(self.load(self.settings), EXISTING)
        self.assertEqual(self.load(self.gemini), EXISTING_GEMINI)
        last = self.installs()[-1]
        self.assertEqual(last["outcome"], "refused")
        self.assertEqual(last["decision"], "deny")
        self.assertIn(needle, last["reason"])

    def test_installs_when_the_main_checkout_matches_origin_main(self):
        rc, out = self.agent()
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.ours(), install.claude_entries(self.command))
        self.assertEqual(
            self.load(self.gemini)["agent-guard"], install.agy_entry(self.command)
        )
        s = self.load(self.settings)
        for event, entries in EXISTING["hooks"].items():
            self.assertEqual(s["hooks"][event], entries)
        self.assertEqual(len(glob.glob(self.settings + ".agent-guard-*.bak")), 1)
        (rec,) = self.installs()
        self.assertEqual(
            {k: rec[k] for k in ("outcome", "decision", "main", "marker", "session")},
            {
                "outcome": "installed",
                "decision": "allow",
                "main": self.co.root,
                "marker": "CLAUDECODE=1",
                "session": "session-under-test",
            },
        )
        self.assertEqual(rec["agent"], "claude-code")
        # Again: nothing changes, and it is logged again.
        before = (self.text(self.settings), self.text(self.gemini))
        rc, out = self.agent()
        self.assertEqual(rc, 0, out)
        self.assertIn("already installed", out)
        self.assertEqual((self.text(self.settings), self.text(self.gemini)), before)
        self.assertEqual(len(self.installs()), 2)

    def test_from_a_worktree_it_installs_for_the_main_checkout(self):
        wt = os.path.join(self.co.tmp, "vitruvian-core-worktrees", "feat-x")
        testlib.git(self.co.root, "worktree", "add", "-q", "--detach", wt)
        rc, out = self.agent(workspace=wt)
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.ours(), install.claude_entries(self.command))

    def test_an_antigravity_marker_is_logged_as_antigravity(self):
        del os.environ["CLAUDECODE"]
        os.environ["ANTIGRAVITY_AGENT"] = "1"
        try:
            rc, out = self.agent()
        finally:
            del os.environ["ANTIGRAVITY_AGENT"]
        self.assertEqual(rc, 0, out)
        rec = self.installs()[-1]
        self.assertEqual(
            (rec["agent"], rec["marker"]), ("antigravity", "ANTIGRAVITY_AGENT=1")
        )

    def test_refused_when_hook_sh_differs_from_origin_main(self):
        with open(os.path.join(self.co.guard_dir, "hook.sh"), "a") as fh:
            fh.write("# an unreviewed local edit\n")
        rc, out = self.agent()
        self.assert_refused(rc, out, "tools/agent-guard/hook.sh in the main checkout")

    def test_refused_when_agent_guard_py_differs_from_origin_main(self):
        with open(os.path.join(self.co.guard_dir, "agent_guard.py"), "a") as fh:
            fh.write("# an unreviewed local edit\n")
        rc, out = self.agent()
        self.assert_refused(rc, out, "agent_guard.py in the main checkout")

    def test_refused_when_a_local_commit_is_ahead_of_origin_main(self):
        with open(os.path.join(self.co.guard_dir, "hook.sh"), "a") as fh:
            fh.write("# committed, never merged\n")
        testlib.git(self.co.root, "commit", "-qam", "local", "--no-gpg-sign")
        rc, out = self.agent()
        self.assert_refused(rc, out, "differs from origin/main's")

    def test_refused_without_origin_main(self):
        testlib.git(self.co.root, "update-ref", "-d", "refs/remotes/origin/main")
        rc, out = self.agent()
        self.assert_refused(rc, out, "`git fetch` there first")

    def test_refused_outside_any_checkout(self):
        rc, out = self.agent(workspace=self.co.out)
        self.assert_refused(rc, out, "not a git checkout")

    def test_refused_for_a_repo_that_is_not_vitruvian_core(self):
        self.co.write("MODULE.bazel", 'module(name = "something_else")\n')
        self.co.commit_to_main("not vitruvian-core")
        rc, out = self.agent()
        self.assert_refused(rc, out, "is not a vitruvian-core checkout")

    def test_refused_when_origin_is_not_vitruvian_core(self):
        for url in (
            "https://github.com/someone/vitruvian-core.git",
            "/tmp/a-local-fake",
        ):
            testlib.git(self.co.root, "remote", "set-url", "origin", url)
            rc, out = self.agent()
            self.assert_refused(
                rc, out, "not github.com/VitruvianSoftware/vitruvian-core"
            )

    def test_refused_while_the_old_copy_is_installed(self):
        old_install(self.home)
        before = (self.text(self.settings), self.text(self.gemini))
        rc, out = self.agent()
        self.assertEqual(rc, 2, out)
        self.assertIn("the first switch from it is James's", out)
        self.assertEqual((self.text(self.settings), self.text(self.gemini)), before)
        self.assertTrue(os.path.isdir(self.idir))
        self.assertEqual(self.installs()[-1]["outcome"], "refused")

    def test_refused_to_move_the_backstop_to_another_checkout(self):
        other = testlib.Checkout()
        try:
            testlib.git(other.root, "remote", "add", "origin", ORIGIN)
            rc, out = self.agent(workspace=other.root)
            self.assertEqual(rc, 0, out)
            before = self.text(self.settings)
            rc, out = self.agent(workspace=self.co.root)
            self.assertEqual(rc, 2, out)
            self.assertIn("moving it is James's", out)
            self.assertEqual(self.text(self.settings), before)
        finally:
            other.close()

    def test_uninstall_and_mode_are_refused(self):
        rc, out = self.agent()
        self.assertEqual(rc, 0, out)
        installed = (self.text(self.settings), self.text(self.gemini))
        rc, out = self.agent("--uninstall")
        self.assertEqual(rc, 2)
        self.assertIn("Removing the backstop is James's job", out)
        rc, out = self.agent("--mode", "git-push=off")
        self.assertEqual(rc, 2)
        self.assertEqual((self.text(self.settings), self.text(self.gemini)), installed)

    def test_dry_run_and_check_still_work_and_say_whether_an_agent_may_install(self):
        rc, out = self.agent("--dry-run")
        self.assertEqual(rc, 0, out)
        self.assertIn("an agent may run this install: yes", out)
        self.assertEqual(self.ours(), [])
        with open(os.path.join(self.co.guard_dir, "hook.sh"), "a") as fh:
            fh.write("# edit\n")
        rc, out = self.agent("--dry-run")
        self.assertIn("an agent may run this install: no, ", out)
        rc, out = self.agent("--check")
        self.assertEqual(rc, 1)  # no backstop yet
        self.assertIn("(an agent may)", out)


class CheckTest(Base):
    def setUp(self):
        super().setUp()
        self.co = testlib.Checkout()
        rc, out = self.run_main(workspace=self.co.root)
        assert rc == 0, out

    def tearDown(self):
        self.co.close()
        super().tearDown()

    def test_passes_with_the_repo_wired_and_the_backstop_installed(self):
        rc, out = self.run_main("--check", workspace=self.co.root)
        self.assertEqual(rc, 0, out)
        self.assertIn("origin/main:", out)
        self.assertIn("backstop runs", out)

    def test_fails_without_the_backstop(self):
        self.run_main("--uninstall")
        rc, out = self.run_main("--check", workspace=self.co.root)
        self.assertEqual(rc, 1)
        self.assertIn("unguarded", out)

    def test_fails_while_the_old_copy_is_installed(self):
        self.run_main("--uninstall")
        old_install(self.home)
        rc, out = self.run_main("--check", workspace=self.co.root)
        self.assertEqual(rc, 1)
        self.assertIn("to migrate", out)

    def test_fails_when_the_main_checkout_moved(self):
        other = testlib.Checkout()
        try:
            self.run_main(workspace=other.root)  # the backstop now points at `other`
        finally:
            other.close()  # ...which is then deleted
        rc, out = self.run_main("--check", workspace=self.co.root)
        self.assertEqual(rc, 1)
        self.assertIn("did the main checkout move?", out)

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
