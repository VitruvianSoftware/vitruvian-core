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

"""Tests for hook.sh (the launcher) and for the repo's two hook files.

The launcher runs in a throwaway git checkout with an origin/main ref: it must
run origin/main's guard, not a local edit; fall back to the working copy when
origin/main is not there; try each python in turn; and find the checkout from
its own path whichever folder it is run from. The wiring tests read the real
.claude/settings.json and .agents/hooks.json and fail if agent-guard's entries
are taken out of either.
"""

import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import install  # noqa: E402
import testlib  # noqa: E402
from testlib import agy, claude, decision  # noqa: E402

BROKEN_GUARD = "this is not python (: an agent's half-finished edit\n"


def fake_python(directory: str, name: str, body: str) -> str:
    """An executable 'python' that just runs body as a shell script."""
    path = os.path.join(directory, name)
    with open(path, "w") as fh:
        fh.write("#!/bin/sh\n" + body + "\n")
    os.chmod(path, 0o755)
    return path


class LauncherTest(unittest.TestCase):
    def setUp(self):
        self.co = testlib.Checkout()

    def tearDown(self):
        self.co.close()

    def test_runs_origin_mains_guard_not_the_local_edit(self):
        # An agent breaks the working copy and switches every category off: it
        # governs nothing, because origin/main's copy is what runs.
        self.co.write("tools/agent-guard/agent_guard.py", BROKEN_GUARD)
        self.co.set_policy({"git-stash": "off", "go": "off"})
        rc, out, err = self.co.run(claude("git stash", self.co.root))
        self.assertEqual(rc, 0, err)
        self.assertEqual(decision(out), "deny")
        rc, out, err = self.co.run(claude("git status", self.co.root))
        self.assertEqual((rc, out), (0, ""), err)
        blob = testlib.git(
            self.co.root, "rev-parse", "origin/main:tools/agent-guard/agent_guard.py"
        ).strip()
        self.assertEqual(self.co.log()[-1]["source"], "origin/main:" + blob)

    def test_a_merged_change_takes_effect(self):
        self.co.set_policy({"git-stash": "off"}, commit=True)
        rc, out, err = self.co.run(claude("git stash", self.co.root))
        self.assertEqual((rc, out), (0, ""), err)

    def test_caches_by_blob_in_the_protected_state_folder(self):
        self.co.run(claude("git status", self.co.root))
        cache = os.path.join(self.co.home, ".local/state/agent-guard/cache")
        g = testlib.git(
            self.co.root, "rev-parse", "origin/main:tools/agent-guard/agent_guard.py"
        ).strip()
        p = testlib.git(
            self.co.root, "rev-parse", "origin/main:tools/agent-guard/policy.json"
        ).strip()
        self.assertTrue(
            os.path.isfile(os.path.join(cache, "guard-" + g, "agent_guard.py"))
        )
        self.assertTrue(os.path.isfile(os.path.join(cache, "policy-%s.json" % p)))
        self.assertEqual(stat.S_IMODE(os.stat(cache).st_mode) & 0o077, 0)
        # The cache is what the guard protects: agents may not write there.
        sys.path.insert(0, testlib.HERE)
        import agent_guard

        self.assertTrue(
            agent_guard.guard_path(
                os.path.join(cache, "guard-" + g, "agent_guard.py"), self.co.home
            )
        )
        # A missing entry is rebuilt on the next call.
        shutil.rmtree(os.path.join(cache, "guard-" + g))
        rc, out, err = self.co.run(claude("git stash", self.co.root))
        self.assertEqual(decision(out), "deny", err)
        self.assertTrue(
            os.path.isfile(os.path.join(cache, "guard-" + g, "agent_guard.py"))
        )

    def test_falls_back_to_the_working_copy_without_origin_main(self):
        self.co.set_policy({"git-stash": "off"})
        testlib.git(self.co.root, "update-ref", "-d", "refs/remotes/origin/main")
        rc, out, err = self.co.run(claude("git stash", self.co.root))
        self.assertEqual((rc, out), (0, ""), err)  # the working copy's policy decided
        self.assertIn("not origin/main's copy", err)
        self.assertTrue(
            self.co.log()[-1]["source"].startswith("working-copy (no origin/main")
        )

    def test_falls_back_when_main_has_no_guard(self):
        testlib.git(
            self.co.root, "rm", "-q", "--cached", "tools/agent-guard/agent_guard.py"
        )
        testlib.git(self.co.root, "commit", "-q", "-m", "drop", "--no-gpg-sign")
        testlib.git(self.co.root, "update-ref", "refs/remotes/origin/main", "HEAD")
        rc, out, err = self.co.run(claude("git stash", self.co.root))
        self.assertEqual(decision(out), "deny", err)
        self.assertTrue(self.co.log()[-1]["source"].startswith("working-copy"))

    def test_falls_back_outside_git(self):
        co = testlib.Checkout(with_git=False)
        try:
            rc, out, err = co.run(claude("git stash", co.root))
            self.assertEqual((rc, decision(out)), (0, "deny"), err)
            self.assertTrue(co.log()[-1]["source"].startswith("working-copy"))
        finally:
            co.close()

    def test_a_main_copy_that_will_not_run_falls_back_to_the_working_copy(self):
        self.co.write("tools/agent-guard/agent_guard.py", BROKEN_GUARD)
        self.co.commit_to_main("broken guard on main")
        shutil.copy(
            os.path.join(testlib.HERE, "agent_guard.py"),
            os.path.join(self.co.guard_dir, "agent_guard.py"),
        )
        rc, out, err = self.co.run(claude("git stash", self.co.root))
        self.assertEqual((rc, decision(out)), (0, "deny"), err)
        self.assertIn("origin/main's copy failed", self.co.log()[-1]["source"])

    def test_tries_each_python_in_turn(self):
        bin_dir = os.path.join(self.co.tmp, "bin")
        os.makedirs(bin_dir)
        broken = fake_python(bin_dir, "python-broken", "exit 1")
        chain = ["/nonexistent/python3", broken, sys.executable]
        self.co.write("tools/agent-guard/hook.sh", testlib.launcher_text(chain))
        rc, out, err = self.co.run(claude("git stash", self.co.root))
        self.assertEqual((rc, decision(out)), (0, "deny"), err)

    def test_exits_1_only_when_no_python_works(self):
        bin_dir = os.path.join(self.co.tmp, "bin")
        os.makedirs(bin_dir)
        broken = fake_python(bin_dir, "python-broken", "exit 1")
        self.co.write(
            "tools/agent-guard/hook.sh",
            testlib.launcher_text(["/nonexistent/python3", broken]),
        )
        rc, out, err = self.co.run(claude("git status", self.co.root))
        self.assertEqual(rc, 1)
        self.assertEqual(out, "")
        self.assertIn("no working python3", err)
        self.assertIn(broken, err)

    def test_agy_runs_it_from_dot_agents(self):
        rc, out, err = self.co.run(
            agy("go vet ./...", self.co.root),
            cwd=os.path.join(self.co.root, ".agents"),
            command=install.AGY_COMMAND,
        )
        self.assertEqual((rc, decision(out, antigravity=True)), (0, "deny"), err)
        rc, out, err = self.co.run(
            agy("git status", self.co.root),
            cwd=os.path.join(self.co.root, ".agents"),
            command=install.AGY_COMMAND,
        )
        self.assertEqual((rc, out), (0, ""), err)
        self.assertEqual(self.co.log()[-1]["agent"], "antigravity")
        self.assertTrue(self.co.log()[-1]["source"].startswith("origin/main:"))

    def test_finds_the_checkout_from_its_own_path_not_the_cwd(self):
        # Claude Code runs it from wherever the agent is, even another checkout.
        other = testlib.Checkout()
        try:
            other.set_policy({"git-stash": "off"}, commit=True)
            rc, out, err = self.co.run(
                claude("git stash", self.co.root), cwd=other.root
            )
            self.assertEqual(decision(out), "deny", err)
        finally:
            other.close()

    def test_the_real_launcher_is_valid_sh_and_lists_pythons_newest_first(self):
        path = os.path.join(testlib.HERE, "hook.sh")
        subprocess.run(["/bin/sh", "-n", path], check=True)
        with open(path) as fh:
            block = testlib.PYTHONS_BLOCK.search(fh.read()).group(0)
        r = subprocess.run(
            ["/bin/sh", "-c", block + 'echo "$pythons"'],
            stdout=subprocess.PIPE,
            check=True,
        )
        chain = r.stdout.decode().split()
        self.assertEqual(
            chain[-2:],
            ["/Library/Developer/CommandLineTools/usr/bin/python3", "/usr/bin/python3"],
        )
        brew = [
            int(p.rsplit("python3.", 1)[1])
            for p in chain[:-2]
            if p.startswith("/opt/homebrew/")
        ]
        self.assertEqual(brew, sorted(brew, reverse=True))

    def test_latency(self):
        self.co.run(claude("git status", self.co.root))  # warm the cache
        n = 10
        start = time.time()
        for _ in range(n):
            self.co.run(claude("git status", self.co.root))
        ms = (time.time() - start) * 1000 / n
        sys.stderr.write("\nlauncher: %.0f ms a call (git status, warm cache)\n" % ms)
        # Generous: CI machines are slow and shared. Locally it is ~40-50 ms.
        self.assertLess(ms, 3000)


class WiringTest(unittest.TestCase):
    """The repo's own hook files: fail if agent-guard is unwired from either."""

    root = testlib.REPO_FILES_ROOT

    def load(self, rel):
        with open(os.path.join(self.root, rel)) as fh:
            return json.load(fh)

    def test_the_repo_is_wired(self):
        self.assertEqual(install.check_wiring(self.root), [])

    def test_claude_entries_are_there_and_only_commands_fail_closed(self):
        entries = self.load(".claude/settings.json")["hooks"]["PreToolUse"]
        ours = [e for e in entries if "agent-guard" in json.dumps(e)]
        self.assertEqual(ours, install.claude_entries())
        self.assertEqual(ours[0]["hooks"][0]["onFailure"], "block")
        self.assertNotIn("onFailure", ours[1]["hooks"][0])
        for e in ours:
            self.assertEqual(
                e["hooks"][0]["command"],
                '/bin/sh "$CLAUDE_PROJECT_DIR/tools/agent-guard/hook.sh"',
            )

    def test_disable_all_hooks_is_pinned_false(self):
        # Project settings outrank user settings, so this keeps a user-level
        # `"disableAllHooks": true` from switching the guard off in the repo.
        self.assertIs(self.load(".claude/settings.json")["disableAllHooks"], False)

    def test_block_queue_bypass_is_kept(self):
        entries = self.load(".claude/settings.json")["hooks"]["PreToolUse"]
        self.assertIn("block-queue-bypass.sh", json.dumps(entries))

    def test_agy_entry_is_grouped_and_runs_from_dot_agents(self):
        spec = self.load(".agents/hooks.json")["agent-guard"]
        self.assertTrue(spec["enabled"])
        group = spec["PreToolUse"][0]
        self.assertEqual(group["matcher"], install.AGY_MATCHER)
        self.assertEqual(
            group["hooks"][0]["command"], "/bin/sh ../tools/agent-guard/hook.sh"
        )
        self.assertTrue(
            os.path.isfile(
                os.path.join(self.root, ".agents", "../tools/agent-guard/hook.sh")
            )
        )

    def test_matchers_cover_every_tool_the_guard_reads(self):
        import re

        sys.path.insert(0, testlib.HERE)
        import agent_guard as g

        claude_tools = [
            t
            for t in list(g.COMMAND_FIELDS) + list(g.FILE_TOOLS)
            if not t[0].islower() or t.startswith("mcp__")
        ]
        for t in claude_tools:
            self.assertTrue(
                re.match(install.COMMAND_MATCHER, t)
                or re.match(install.FILE_MATCHER, t),
                t,
            )
        agy_tools = [
            t
            for t in list(g.COMMAND_FIELDS) + list(g.FILE_TOOLS)
            if t[0].islower() and not t.startswith("mcp__")
        ]
        agy_tools += [g.AGY_MANAGE_TASK, g.AGY_GIT_COMMIT]
        for t in agy_tools:
            self.assertIn(t, install.AGY_MATCHER.split("|"), t)

    def test_unwiring_either_file_is_caught(self):
        tmp = tempfile.mkdtemp(prefix="agent-guard-wiring-")
        try:

            def fresh():
                shutil.rmtree(tmp, ignore_errors=True)
                for rel in (
                    ".claude/settings.json",
                    ".agents/hooks.json",
                    "tools/agent-guard/hook.sh",
                ):
                    os.makedirs(os.path.join(tmp, os.path.dirname(rel)), exist_ok=True)
                    shutil.copy(os.path.join(self.root, rel), os.path.join(tmp, rel))
                self.assertEqual(install.check_wiring(tmp), [])

            def edit(rel, change):
                path = os.path.join(tmp, rel)
                with open(path) as fh:
                    data = json.load(fh)
                change(data)
                with open(path, "w") as fh:
                    json.dump(data, fh)

            def drop(i):
                return lambda d: d["hooks"]["PreToolUse"].pop(i)

            claude_mutations = {
                "command-tool entry removed": drop(1),
                "file-tool entry removed": drop(2),
                "onFailure dropped": lambda d: d["hooks"]["PreToolUse"][1]["hooks"][
                    0
                ].pop("onFailure"),
                "matcher narrowed": lambda d: d["hooks"]["PreToolUse"][1].update(
                    matcher="Bash"
                ),
                "all hooks removed": lambda d: d.pop("hooks"),
                "disableAllHooks dropped": lambda d: d.pop("disableAllHooks"),
                "disableAllHooks true": lambda d: d.update(disableAllHooks=True),
            }
            for name, change in claude_mutations.items():
                fresh()
                edit(".claude/settings.json", change)
                self.assertNotEqual(install.check_wiring(tmp), [], name)
            agy_mutations = {
                "entry removed": lambda d: d.pop("agent-guard"),
                "disabled": lambda d: d["agent-guard"].update(enabled=False),
                "flat shape (agy ignores it)": lambda d: d["agent-guard"].update(
                    PreToolUse=[
                        {
                            "matcher": install.AGY_MATCHER,
                            "type": "command",
                            "command": install.AGY_COMMAND,
                        }
                    ]
                ),
                "absolute path": lambda d: d["agent-guard"]["PreToolUse"][0]["hooks"][
                    0
                ].update(command="/bin/sh /x/hook.sh"),
            }
            for name, change in agy_mutations.items():
                fresh()
                edit(".agents/hooks.json", change)
                self.assertNotEqual(install.check_wiring(tmp), [], name)
            fresh()
            os.remove(os.path.join(tmp, ".agents/hooks.json"))
            self.assertNotEqual(install.check_wiring(tmp), [])
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
