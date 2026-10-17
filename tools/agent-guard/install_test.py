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

"""Tests for install.py against a temporary HOME: merge, idempotence, dry run,
uninstall, the two hook entries, the self-test and rollback, and the refusals."""

import contextlib
import glob
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from typing import Any, Dict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agent_guard  # noqa: E402
import install  # noqa: E402

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

# The shape of James's ~/.gemini/config/hooks.json before agent-guard: one
# named hook, flat because PreInvocation takes the flat shape.
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

# Stub files that satisfy every install prerequisite.
CHECKOUT = {
    "tools/git/BUILD": 'sh_binary(name = "commit")\nsh_binary(name = "push")\nsh_binary(name = "sync")\n',
    "tools/secret-scan/BUILD": 'sh_binary(name = "secret-scan")\n',
    "tools/agent-app/agent-app.sh": "case $1 in pr-create) ;; pr-enqueue) ;; esac\n",
}


def write_checkout(root, **override):
    for rel, text in CHECKOUT.items():
        text = override.get(rel, text)
        if text is None:
            continue
        os.makedirs(os.path.dirname(os.path.join(root, rel)), exist_ok=True)
        with open(os.path.join(root, rel), "w") as fh:
            fh.write(text)


def fake_repo(parent):
    repo = os.path.join(parent, "repo")
    os.makedirs(repo, exist_ok=True)
    with open(os.path.join(repo, "MODULE.bazel"), "w") as fh:
        fh.write('module(name = "vitruvian_core")\n')
    return repo


AGENT_ENV = ("CLAUDECODE", "ANTIGRAVITY_AGENT", "GEMINI_CLI")


class InstallTest(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp(prefix="agent-guard-home-")
        os.makedirs(os.path.join(self.home, ".claude"))
        self.settings = os.path.join(self.home, ".claude", "settings.json")
        with open(self.settings, "w") as fh:
            json.dump(EXISTING, fh, indent=2)
        self.gemini_dir = os.path.join(self.home, ".gemini", "config")
        os.makedirs(self.gemini_dir)
        self.gemini = os.path.join(self.gemini_dir, "hooks.json")
        with open(self.gemini, "w") as fh:
            json.dump(EXISTING_GEMINI, fh, indent=2)
            fh.write("\n")
        # A checkout that already has the targets the guard points to.
        self.workspace = os.path.join(self.home, "checkout")
        write_checkout(self.workspace)
        self.idir = os.path.join(self.home, ".local/share/agent-guard")
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

    def run_install(self, *args, python=None, workspace=None, fallback=None):
        out, err = io.StringIO(), io.StringIO()
        argv = [
            "--home",
            self.home,
            "--workspace",
            workspace or self.workspace,
            "--python",
            python or sys.executable,
            "--on-failure",
            "block",
        ]
        # Default: no Homebrew lookup, so the tests are hermetic and quick.
        for f in fallback if fallback is not None else [sys.executable]:
            argv += ["--fallback-python", f]
        argv += list(args)
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = install.main(argv)
        return rc, out.getvalue() + err.getvalue()

    def load(self):
        with open(self.settings) as fh:
            return json.load(fh)

    def ours(self, settings):
        found = []
        for event, entries in settings.get("hooks", {}).items():
            for e in entries:
                for h in e.get("hooks", []):
                    if install.MARKER_RE.search(h.get("command", "")):
                        found.append((event, e, h))
        return found

    def snapshot(self):
        with open(self.settings) as fh:
            return fh.read()

    def gemini_text(self):
        with open(self.gemini) as fh:
            return fh.read()

    def load_gemini(self):
        with open(self.gemini) as fh:
            return json.load(fh)

    def agy_hook(self, payload, cwd=None):
        """Run the installed hook the way agy does: from the hooks.json folder."""
        command = self.ours(self.load())[0][2]["command"]
        r = subprocess.run(
            command,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
            cwd=cwd or self.gemini_dir,
            input=json.dumps(payload).encode(),
            env=dict(os.environ, HOME=self.home),
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout) if r.stdout.strip() else None

    # --- merging ------------------------------------------------------------
    def test_merge_keeps_every_existing_hook(self):
        rc, _ = self.run_install()
        self.assertEqual(rc, 0)
        s = self.load()
        for event in ("PermissionRequest", "Stop", "UserPromptSubmit"):
            self.assertEqual(s["hooks"][event], EXISTING["hooks"][event], event)
        self.assertEqual(s["effortLevel"], "high")
        self.assertEqual(s["remoteControlAtStartup"], True)

    def test_two_entries_and_only_commands_fail_closed(self):
        self.run_install()
        ours = self.ours(self.load())
        self.assertEqual([e for e, _x, _y in ours], ["PreToolUse", "PreToolUse"])
        by_matcher = {entry["matcher"]: handler for _e, entry, handler in ours}
        self.assertEqual(
            set(by_matcher), {install.COMMAND_MATCHER, install.FILE_MATCHER}
        )
        self.assertEqual(by_matcher[install.COMMAND_MATCHER].get("onFailure"), "block")
        self.assertNotIn("onFailure", by_matcher[install.FILE_MATCHER])
        self.assertIn(
            os.path.join(self.idir, "hook.sh"),
            by_matcher[install.COMMAND_MATCHER]["command"],
        )

    def test_matchers_cover_the_right_tools(self):
        cmd, files = (
            re.compile(install.COMMAND_MATCHER),
            re.compile(install.FILE_MATCHER),
        )
        dc = "mcp__plugin_desktop-commander_desktop-commander__"
        for tool in (
            "Bash",
            "Monitor",
            "mcp__terminal__run_in_terminal",
            "mcp__ccd_pr__set_auto_merge",
            dc + "start_process",
            dc + "interact_with_process",
            "mcp__kubernetes__kubectl_apply",
            "mcp__Kubernetes_MCP_Server__exec_in_pod",
        ):
            self.assertTrue(cmd.search(tool), tool)
            self.assertFalse(files.search(tool), tool)
        for tool in (
            "Edit",
            "Write",
            "MultiEdit",
            "NotebookEdit",
            dc + "write_file",
            dc + "edit_block",
            dc + "move_file",
            dc + "create_directory",
            dc + "write_pdf",
        ):
            self.assertTrue(files.search(tool), tool)
            self.assertFalse(cmd.search(tool), tool)
            self.assertIn(tool, agent_guard.FILE_TOOLS)
        for tool in (
            "Read",
            "Grep",
            "mcp__kubernetes__kubectl_get",
            "BashOutput",
            dc + "read_file",
        ):
            self.assertFalse(cmd.search(tool) or files.search(tool), tool)

    def test_replaces_an_old_entry_rather_than_adding_one(self):
        s = json.loads(json.dumps(EXISTING))
        s["hooks"]["PreToolUse"] = [
            {
                "matcher": "Bash",
                "hooks": [
                    {
                        "type": "command",
                        "command": "/old/agent-guard/agent_guard.py",
                        "timeout": 3,
                    }
                ],
            },
            {
                "matcher": "Bash",
                "hooks": [{"type": "command", "command": "/other/hook.sh"}],
            },
        ]
        with open(self.settings, "w") as fh:
            json.dump(s, fh)
        self.run_install()
        pre = self.load()["hooks"]["PreToolUse"]
        self.assertEqual(
            pre[0],
            {
                "matcher": "Bash",
                "hooks": [{"type": "command", "command": "/other/hook.sh"}],
            },
        )
        self.assertEqual(len(self.ours(self.load())), 2)

    def test_keeps_the_desktop_apps_json_style(self):
        # The desktop app writes `"key" : value`, escaped slashes, no final newline.
        text = json.dumps(EXISTING, indent=2, separators=(",", " : ")).replace(
            "/", "\\/"
        )
        with open(self.settings, "w") as fh:
            fh.write(text)
        _rc, out = self.run_install("--dry-run")
        removed = [
            line
            for line in out.splitlines()
            if line.startswith("-") and not line.startswith("---")
        ]
        self.assertEqual(removed, [], out)  # only additions
        self.run_install()
        after = self.snapshot()
        self.assertTrue(after.startswith(text[: text.index('"hooks"')]))
        self.assertFalse(after.endswith("\n"))
        self.assertIn('"PreToolUse" : [', after)
        self.run_install("--uninstall")
        self.assertEqual(self.snapshot(), text)

    def test_missing_settings_file_is_created(self):
        os.remove(self.settings)
        self.run_install()
        self.assertEqual(len(self.ours(self.load())), 2)

    def test_invalid_settings_are_never_clobbered(self):
        with open(self.settings, "w") as fh:
            fh.write("{broken")
        with self.assertRaises(SystemExit):
            self.run_install()
        self.assertEqual(self.snapshot(), "{broken")

    # --- the installed copy -------------------------------------------------
    def test_installs_a_versioned_copy_with_a_launcher(self):
        rc, out = self.run_install()
        self.assertEqual(rc, 0, out)
        for name in (
            "agent_guard.py",
            "policy.json",
            "hook.py",
            "hook.sh",
            "VERSION.json",
        ):
            self.assertTrue(os.path.isfile(os.path.join(self.idir, name)), name)
        with open(os.path.join(self.idir, "hook.py")) as fh:
            self.assertEqual(len(fh.read().strip().splitlines()), 2)
        with open(os.path.join(self.idir, "VERSION.json")) as fh:
            stamp = json.load(fh)
        self.assertEqual(stamp["version"], agent_guard.VERSION)
        self.assertEqual(stamp["sha256"], install.sha256_files(self.idir))
        self.assertIn("self-test passed", out)
        # The self-test imported the guard through the launcher: its bytecode is cached.
        self.assertTrue(
            glob.glob(os.path.join(self.idir, "__pycache__", "agent_guard*.pyc"))
        )
        self.assertTrue(
            os.path.isfile(
                os.path.join(self.home, ".local/state/agent-guard/log.jsonl")
            )
        )

    def test_idempotent(self):
        self.run_install()
        first = self.snapshot()
        backups = glob.glob(self.settings + ".agent-guard-*.bak")
        rc, out = self.run_install()
        self.assertEqual(rc, 0)
        self.assertIn("already installed and up to date", out)
        self.assertEqual(self.snapshot(), first)
        self.assertEqual(glob.glob(self.settings + ".agent-guard-*.bak"), backups)
        self.assertEqual(len(self.ours(self.load())), 2)

    def test_backs_up_before_writing(self):
        original = self.snapshot()
        self.run_install()
        backups = glob.glob(self.settings + ".agent-guard-*.bak")
        self.assertEqual(len(backups), 1)
        with open(backups[0]) as fh:
            self.assertEqual(fh.read(), original)

    # --- self-test and rollback --------------------------------------------
    def test_a_broken_hook_is_rolled_back(self):
        original = self.snapshot()
        original_gemini = self.gemini_text()
        rc, out = self.run_install(python="/usr/bin/false")
        self.assertEqual(rc, 4)
        self.assertIn("self-test", out)
        self.assertIn("put back", out)
        self.assertEqual(self.snapshot(), original)
        self.assertEqual(self.gemini_text(), original_gemini)
        self.assertFalse(os.path.exists(self.idir))
        self.assertEqual(glob.glob(self.idir + ".previous-*"), [])

    def test_rollback_restores_the_previous_copy(self):
        self.run_install()
        before = self.snapshot()
        with open(os.path.join(self.idir, "agent_guard.py")) as fh:
            old_guard = fh.read()
        rc, _ = self.run_install("--mode", "git-push=warn", python="/usr/bin/false")
        self.assertEqual(rc, 4)
        self.assertEqual(self.snapshot(), before)
        with open(os.path.join(self.idir, "agent_guard.py")) as fh:
            self.assertEqual(fh.read(), old_guard)
        with open(os.path.join(self.idir, "policy.json")) as fh:
            self.assertEqual(json.load(fh)["categories"]["git-push"]["mode"], "enforce")

    def test_check_runs_the_self_test(self):
        rc, out = self.run_install("--check")
        self.assertEqual(rc, 1)
        self.assertIn("DRIFT", out)
        self.run_install()
        rc, out = self.run_install("--check")
        self.assertEqual(rc, 0, out)
        with open(os.path.join(self.idir, "hook.py"), "w") as fh:
            fh.write("import sys; sys.exit(3)\n")
        rc, out = self.run_install("--check")
        self.assertEqual(rc, 1)
        self.assertIn("does not work", out)

    # --- refusals ----------------------------------------------------------
    def test_refuses_before_the_targets_land(self):
        original = self.snapshot()
        bare = os.path.join(self.home, "old-main")
        os.makedirs(bare)
        rc, out = self.run_install(workspace=bare)
        self.assertEqual(rc, 3)
        self.assertIn("//tools/git:commit", out)
        self.assertIn("//tools/secret-scan", out)
        self.assertEqual(self.snapshot(), original)
        self.assertFalse(os.path.exists(self.idir))
        rc, out = self.run_install("--dry-run", workspace=bare)
        self.assertEqual(rc, 0)
        self.assertIn("would be REFUSED", out)

    def test_refuses_until_each_target_is_really_there(self):
        cases = {
            "//tools/git:sync": {
                "tools/git/BUILD": 'sh_binary(name = "commit")\nsh_binary(name = "push")\n'
            },
            "//tools/git:commit": {"tools/git/BUILD": "# empty BUILD\n"},
            "pr-enqueue": {
                "tools/agent-app/agent-app.sh": "case $1 in pr-create) ;; esac\n"
            },
            "//tools/secret-scan": {"tools/secret-scan/BUILD": None},
        }
        for i, (needle, override) in enumerate(cases.items()):
            root = os.path.join(self.home, "partial-%d" % i)
            write_checkout(root, **override)
            rc, out = self.run_install(workspace=root)
            self.assertEqual(rc, 3, needle)
            self.assertIn(needle, out)
        self.assertFalse(os.path.exists(self.idir))

    def test_hook_falls_back_when_its_python_disappears(self):
        # The first interpreter is a link that vanishes, as a Homebrew cleanup would.
        links = tempfile.mkdtemp(prefix="agent-guard-py-")
        first = os.path.join(links, "python3.99")
        os.symlink(sys.executable, first)
        try:
            rc, out = self.run_install(python=first, fallback=[sys.executable])
            self.assertEqual(rc, 0, out)
            with open(os.path.join(self.idir, "hook.sh")) as fh:
                script = fh.read()
            self.assertLess(script.index(first), script.index(sys.executable))
            os.remove(first)
            repo = fake_repo(self.home)
            command = self.ours(self.load())[0][2]["command"]
            for sample, want in (("git stash", "deny"), ("git status", None)):
                r = subprocess.run(
                    command,
                    shell=True,
                    stdout=subprocess.PIPE,
                    timeout=60,
                    input=json.dumps(
                        {
                            "tool_name": "Bash",
                            "cwd": repo,
                            "tool_input": {"command": sample},
                        }
                    ).encode(),
                    env=dict(os.environ, HOME=self.home),
                )
                self.assertEqual(r.returncode, 0, sample)
                got = (
                    json.loads(r.stdout)["hookSpecificOutput"]["permissionDecision"]
                    if r.stdout.strip()
                    else None
                )
                self.assertEqual(got, want, sample)
            # Bytecode was cached for the fallback interpreter too.
            tag = sys.implementation.cache_tag
            self.assertTrue(
                glob.glob(
                    os.path.join(self.idir, "__pycache__", "agent_guard.%s*.pyc" % tag)
                )
            )
        finally:
            shutil.rmtree(links, ignore_errors=True)

    def test_launcher_exits_nonzero_only_when_nothing_works(self):
        os.makedirs(self.idir)
        script = os.path.join(self.idir, "hook.sh")
        with open(script, "w") as fh:
            fh.write(
                install.runner_text(
                    ["/nonexistent/python3.98", "/usr/bin/false"], self.idir
                )
            )
        r = subprocess.run(
            ["/bin/sh", script],
            input=b"{}",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        self.assertEqual(r.returncode, 1)
        self.assertIn(b"no working python3", r.stderr)

    def test_interpreter_chain_order(self):
        chain = install.interpreter_chain(
            "/a/python3.15", ["/b/python3.12", "/a/python3.15"]
        )
        self.assertEqual(
            chain, ["/a/python3.15", "/b/python3.12"] + list(install.SYSTEM_PYTHONS)
        )

    def test_refuses_inside_any_agent_session(self):
        for marker in (
            "CLAUDECODE",
            "ANTIGRAVITY_AGENT",
            "GEMINI_CLI",
            "ANTIGRAVITY_LS_ADDRESS",
        ):
            os.environ[marker] = "1"
            try:
                rc, _ = self.run_install("--dry-run")
                self.assertEqual(rc, 0, marker)
                for args in ((), ("--uninstall",), ("--mode", "git-push=off")):
                    rc, out = self.run_install(*args)
                    self.assertEqual(rc, 2, (marker, args))
                    self.assertIn(marker, out)
            finally:
                del os.environ[marker]
        self.assertEqual(self.ours(self.load()), [])

    def test_bad_mode_is_refused(self):
        for bad in ("nope=warn", "git-push=maybe", "git-push"):
            with self.assertRaises(SystemExit):
                self.run_install("--mode", bad)

    # --- dry run, modes, uninstall -----------------------------------------
    def test_dry_run_writes_nothing_and_prints_the_diff(self):
        before = self.snapshot()
        rc, out = self.run_install("--dry-run")
        self.assertEqual(rc, 0)
        self.assertIn("+++", out)
        self.assertIn("PreToolUse", out)
        self.assertIn("would write", out)
        self.assertIn("Antigravity", out)
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(os.path.exists(os.path.join(self.home, ".local")))
        self.assertEqual(glob.glob(self.settings + ".agent-guard-*.bak"), [])

    def test_mode_overrides_change_the_installed_copy_only(self):
        self.run_install("--mode", "git-push=warn", "--mode", "go=off")
        with open(os.path.join(self.idir, "policy.json")) as fh:
            installed = json.load(fh)
        self.assertEqual(installed["categories"]["git-push"]["mode"], "warn")
        self.assertEqual(installed["categories"]["go"]["mode"], "off")
        self.assertEqual(installed["categories"]["git-commit"]["mode"], "enforce")
        with open(agent_guard.default_policy_path()) as fh:
            self.assertEqual(json.load(fh)["categories"]["git-push"]["mode"], "enforce")
        self.run_install()  # a plain reinstall keeps the modes set earlier
        with open(os.path.join(self.idir, "policy.json")) as fh:
            self.assertEqual(json.load(fh)["categories"]["git-push"]["mode"], "warn")

    def test_uninstall_restores_the_original_hooks(self):
        self.run_install()
        rc, _ = self.run_install("--uninstall")
        self.assertEqual(rc, 0)
        self.assertEqual(self.load(), EXISTING)
        self.assertFalse(os.path.exists(self.idir))
        _rc, out = self.run_install("--uninstall")
        self.assertIn("no agent-guard hook to remove", out)

    def test_uninstall_works_without_the_targets(self):
        self.run_install()
        rc, _ = self.run_install(
            "--uninstall", workspace=os.path.join(self.home, "nowhere")
        )
        self.assertEqual(rc, 0)
        self.assertEqual(self.load(), EXISTING)

    def test_uninstall_dry_run(self):
        self.run_install()
        before = self.snapshot()
        _rc, out = self.run_install("--uninstall", "--dry-run")
        self.assertIn("would remove", out)
        self.assertEqual(self.snapshot(), before)

    def test_on_failure_can_be_left_out(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            install.main(
                [
                    "--home",
                    self.home,
                    "--workspace",
                    self.workspace,
                    "--python",
                    sys.executable,
                    "--on-failure",
                    "allow",
                ]
            )
        self.assertTrue(
            all("onFailure" not in h for _e, _x, h in self.ours(self.load()))
        )

    # --- Antigravity (agy) -------------------------------------------------
    def test_antigravity_entry_is_merged_in_the_grouped_shape(self):
        rc, out = self.run_install()
        self.assertEqual(rc, 0, out)
        self.assertIn("Antigravity hook written to", out)
        hooks = self.load_gemini()
        self.assertEqual(list(hooks), ["response-contract", "agent-guard"])
        self.assertEqual(
            hooks["response-contract"], EXISTING_GEMINI["response-contract"]
        )
        command = self.ours(self.load())[0][2]["command"]
        entry = hooks["agent-guard"]
        self.assertEqual(entry, install.agy_entry(command))
        self.assertIs(entry["enabled"], True)
        (group,) = entry["PreToolUse"]
        # Grouped: matcher beside a hooks list, never type/command beside matcher
        # (agy loads that flat shape but silently ignores it).
        self.assertEqual(set(group), {"matcher", "hooks"})
        self.assertEqual(group["matcher"], install.AGY_MATCHER)
        self.assertEqual(
            group["hooks"],
            [{"type": "command", "command": command, "timeout": install.HOOK_TIMEOUT}],
        )

    def test_antigravity_matcher_covers_what_the_guard_reads(self):
        m = re.compile(install.AGY_MATCHER)
        agy_tools = [
            "run_command",
            "shell_exec",
            "send_command_input",
            "manage_task",
            "git_commit",
            "write_to_file",
            "replace_file_content",
            "multi_replace_file_content",
            "notebook_edit",
        ]
        for tool in agy_tools:
            self.assertTrue(m.search(tool), tool)
            self.assertTrue(
                tool in agent_guard.COMMAND_FIELDS
                or tool in agent_guard.FILE_TOOLS
                or tool in (agent_guard.AGY_MANAGE_TASK, agent_guard.AGY_GIT_COMMIT),
                tool,
            )
        self.assertEqual(sorted(install.AGY_MATCHER.split("|")), sorted(agy_tools))
        for tool in ("view_file", "list_dir", "grep_search", "read_url_content"):
            self.assertFalse(m.search(tool), tool)

    def test_antigravity_hand_wired_entry_is_replaced_in_place(self):
        command = install.hook_command(self.home)
        hand = dict(EXISTING_GEMINI)
        hand["agent-guard"] = {
            "enabled": True,
            "PreToolUse": [
                {
                    "matcher": "run_command",
                    "hooks": [{"type": "command", "command": command, "timeout": 10}],
                }
            ],
        }
        # An old flat-shape try under another name, which agy ignored.
        hand["guard-try"] = {
            "PreToolUse": [
                {"matcher": "run_command", "type": "command", "command": command}
            ]
        }
        hand["later"] = {"Stop": [{"type": "command", "command": "/x/stop.sh"}]}
        with open(self.gemini, "w") as fh:
            json.dump(hand, fh, indent=2)
        rc, out = self.run_install()
        self.assertEqual(rc, 0, out)
        hooks = self.load_gemini()
        self.assertEqual(list(hooks), ["response-contract", "agent-guard", "later"])
        self.assertEqual(hooks["agent-guard"], install.agy_entry(command))
        self.assertEqual(hooks["later"], hand["later"])

    def test_antigravity_idempotent_with_one_backup(self):
        original = self.gemini_text()
        self.run_install()
        after = self.gemini_text()
        backups = glob.glob(self.gemini + ".agent-guard-*.bak")
        self.assertEqual(len(backups), 1)
        with open(backups[0]) as fh:
            self.assertEqual(fh.read(), original)
        rc, out = self.run_install()
        self.assertEqual(rc, 0)
        self.assertIn("already installed and up to date", out)
        self.assertEqual(self.gemini_text(), after)
        self.assertEqual(glob.glob(self.gemini + ".agent-guard-*.bak"), backups)

    def test_antigravity_only_change_is_still_installed(self):
        # Installed before this change: Claude Code wired, agy not.
        self.run_install()
        with open(self.gemini, "w") as fh:
            json.dump(EXISTING_GEMINI, fh, indent=2)
        rc, out = self.run_install()
        self.assertEqual(rc, 0, out)
        self.assertIn("agent-guard", self.load_gemini())

    def test_antigravity_dry_run_writes_nothing(self):
        before = self.gemini_text()
        rc, out = self.run_install("--dry-run")
        self.assertEqual(rc, 0)
        self.assertIn("Antigravity hooks:", out)
        self.assertIn(install.AGY_MATCHER, out)
        self.assertEqual(self.gemini_text(), before)
        self.assertEqual(glob.glob(self.gemini + ".agent-guard-*.bak"), [])

    def test_antigravity_uninstall_removes_only_ours(self):
        self.run_install()
        _rc, out = self.run_install("--uninstall", "--dry-run")
        self.assertIn("Antigravity hooks:", out)
        self.assertIn("agent-guard", self.load_gemini())
        rc, out = self.run_install("--uninstall")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.load_gemini(), EXISTING_GEMINI)
        _rc, out = self.run_install("--uninstall")
        self.assertIn("Antigravity hooks: no agent-guard hook to remove", out)

    def test_antigravity_check(self):
        self.run_install()
        rc, out = self.run_install("--check")
        self.assertEqual(rc, 0, out)
        self.assertIn("both hook formats", out)
        hooks = self.load_gemini()
        hooks["agent-guard"]["PreToolUse"][0]["matcher"] = "run_command"
        with open(self.gemini, "w") as fh:
            json.dump(hooks, fh)
        rc, out = self.run_install("--check")
        self.assertEqual(rc, 1)
        self.assertIn(self.gemini, out)

    def test_antigravity_not_installed_is_left_alone(self):
        shutil.rmtree(os.path.join(self.home, ".gemini"))
        rc, out = self.run_install()
        self.assertEqual(rc, 0, out)
        self.assertIn("not found", out)
        self.assertFalse(os.path.exists(os.path.join(self.home, ".gemini")))
        rc, out = self.run_install("--check")
        self.assertEqual(rc, 0, out)

    def test_broken_hooks_json_blocks_install_not_uninstall(self):
        self.run_install()
        with open(self.gemini, "w") as fh:
            fh.write("{broken")
        claude_before = self.snapshot()
        with self.assertRaises(SystemExit):
            self.run_install("--mode", "go=warn")
        self.assertEqual(self.snapshot(), claude_before)
        rc, out = self.run_install("--check")
        self.assertEqual(rc, 1)
        self.assertIn("not valid JSON", out)
        rc, _out = self.run_install("--uninstall")
        self.assertEqual(rc, 0)
        self.assertEqual(self.load(), EXISTING)
        self.assertEqual(self.gemini_text(), "{broken")

    def test_installed_hook_answers_agys_real_payload(self):
        self.run_install()
        repo = fake_repo(self.home)

        def payload(command, cwd, workspace):
            p = {
                "toolCall": {
                    "name": "run_command",
                    "args": {
                        "CommandLine": command,
                        "WaitMsBeforeAsync": 5000,
                        "toolAction": "Running command",
                        "toolSummary": "Run it",
                    },
                },
                "stepIdx": 3,
                "conversationId": "11111111-2222-4333-8444-555555555555",
                "workspacePaths": workspace,
                "transcriptPath": "/fake/transcript.jsonl",
                "artifactDirectoryPath": "/fake/artifacts",
                "modelName": "auto",
            }
            if cwd:
                p["toolCall"]["args"]["Cwd"] = cwd
            return p

        out = self.agy_hook(payload("go vet ./...", repo, [repo]))
        self.assertEqual(out["decision"], "deny")
        self.assertIn("bazel test", out["reason"])
        self.assertIsNone(self.agy_hook(payload("git status", repo, [repo])))
        # No Cwd: the workspace decides, not the hooks.json folder it runs in.
        self.assertEqual(
            self.agy_hook(payload("go vet ./...", None, [repo]))["decision"], "deny"
        )
        self.assertEqual(
            self.agy_hook(payload("go vet ./...", None, []))["decision"], "deny"
        )
        with open(agent_guard.log_path(self.home)) as fh:
            recs = [json.loads(line) for line in fh]
        mine = [
            r
            for r in recs
            if r.get("session") == "11111111-2222-4333-8444-555555555555"
        ]
        self.assertEqual(len(mine), 4)
        self.assertEqual(
            [(r["agent"], r["cwd"]) for r in mine[:3]],
            [("antigravity", repo)] * 3,
        )
        self.assertEqual((mine[3]["cwd"], mine[3]["scope"]), ("", "unknown"))

    def test_python_preference_puts_apples_shim_last(self):
        cands = install.python_candidates()
        self.assertEqual(cands[-1], "/usr/bin/python3")
        self.assertEqual(
            cands[-2], "/Library/Developer/CommandLineTools/usr/bin/python3"
        )
        self.assertTrue(all(os.path.isabs(c) for c in cands))


if __name__ == "__main__":
    unittest.main(verbosity=2)
