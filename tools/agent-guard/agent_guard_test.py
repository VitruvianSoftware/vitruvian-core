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

"""Tests for agent_guard.py: the decision table, redaction, scope, modes, the hook I/O.

The table is built from what agents actually ran between 2026-10-09 and 10-16
(the design's inventory), plus every escape hatch the guard has to see through.
"""

import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from collections import Counter
from typing import Any, Dict
from unittest import mock

# The folder name has a hyphen, so it cannot be a package: import by path.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agent_guard as g  # noqa: E402

A, D = "allow", "deny"

# (command, decision, category or None, git-state key). {repo} is a fake
# vitruvian-core checkout, {wt} a linked worktree of it, {out} a directory
# outside it, {home} the fake HOME.
# The rows live in testdata/decision_table.json, which the Rust tests
# (tests/table.rs) read too: one table for both guards. A bare string in it is
# a comment (the section headings and their reasons).
TABLE_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "testdata", "decision_table.json"
)
with open(TABLE_PATH, encoding="utf-8") as _fh:
    TABLE = [tuple(_row) for _row in json.load(_fh) if not isinstance(_row, str)]


# Too many commands to check in time: refused inside the repo (generated here
# rather than spelled out). Real commands have tens; the cap is 20,000.
TABLE += [
    ("true; " * 25000, D, "oversize", ""),
    ("echo `x`" * 25000, D, "oversize", ""),
    ("true; " * 5000 + "git status", A, None, ""),
    ("true; " * 5000 + "git push", D, "git-push", ""),
]


def _git_state(repo, wt):
    conflicted = [os.path.join(repo, "src", "conflicted.go")]
    states = {
        "": g.GitState(primary=True),
        "primary": g.GitState(primary=True),
        "worktree": g.GitState(primary=False),
        "merging": g.GitState(merge=True, unmerged=conflicted),
        "rebasing": g.GitState(rebase=True, unmerged=conflicted),
        "picking": g.GitState(cherry_pick=True, unmerged=conflicted),
        "out": g.GitState(primary=True),
    }
    return states


class Fixture(object):
    def __init__(self):
        # Not under TEST_TMPDIR: inside Bazel that sits below an execroot whose
        # MODULE.bazel would make the "outside" directory look inside.
        self.tmp = tempfile.mkdtemp(
            prefix="agent-guard-test-",
            dir="/tmp" if os.access("/tmp", os.W_OK) else None,
        )
        self.home = os.path.join(self.tmp, "home")
        self.repo = os.path.join(self.tmp, "vitruvian-core")
        self.wt = os.path.join(self.tmp, "vitruvian-core-worktrees", "feat-x")
        self.out = os.path.join(self.tmp, "elsewhere")
        for d in (self.home, self.out, os.path.join(self.repo, "src"), self.wt):
            os.makedirs(d)
        for root in (self.repo, self.wt):
            with open(os.path.join(root, "MODULE.bazel"), "w") as fh:
                fh.write('module(\n    name = "vitruvian_core",\n)\n')
            with open(os.path.join(root, "README.md"), "w") as fh:
                fh.write("hi\n")
        os.makedirs(os.path.join(self.repo, ".git"))
        with open(os.path.join(self.wt, ".git"), "w") as fh:
            fh.write("gitdir: %s/.git/worktrees/feat-x\n" % self.repo)
        with open(os.path.join(self.repo, "src", "main.go"), "w") as fh:
            fh.write("package main\n")
        self.states = _git_state(self.repo, self.wt)
        g._scope_cache.clear()
        g._root_cache.clear()
        if g.repo_root_of(self.out) is not None:
            raise AssertionError(
                "fixture's outside dir %s is inside a vitruvian-core checkout"
                % self.out
            )

    def fmt(self, s):
        return (
            s.replace("{repo}", self.repo)
            .replace("{wt}", self.wt)
            .replace("{out}", self.out)
            .replace("{home}", self.home)
        )

    def run(self, command, key="", modes=None):
        cwd = self.out if key == "out" else self.repo
        state = self.states[key]
        return g.evaluate(
            self.fmt(command),
            cwd,
            modes=modes,
            home=self.home,
            git_state=lambda _d: state,
        )

    def close(self):
        shutil.rmtree(self.tmp, ignore_errors=True)


class DecisionTableTest(unittest.TestCase):
    """Command shapes. The fixture is not a real git checkout, so whether the
    installer there is origin/main's is taken as yes here; InstallerSourceTest
    checks that part against a real one."""

    @classmethod
    def setUpClass(cls):
        cls.fx = Fixture()
        cls._patch = mock.patch.object(g, "installer_problem", return_value="")
        cls._patch.start()

    @classmethod
    def tearDownClass(cls):
        cls._patch.stop()
        cls.fx.close()

    def test_table_is_big_enough(self):
        self.assertGreaterEqual(len(TABLE), 150)

    def test_every_row(self):
        failures = []
        for command, want, cat, key in TABLE:
            d = self.fx.run(command, key)
            if d.decision != want or d.category != cat:
                failures.append(
                    "%r [%s]: want %s/%s, got %s/%s"
                    % (command, key or "-", want, cat, d.decision, d.category)
                )
        self.assertEqual(failures, [], "\n" + "\n".join(failures))

    def test_every_category_has_a_blocked_row(self):
        covered = {cat for _c, want, cat, _k in TABLE if want == D}
        self.assertEqual(set(g.CATEGORIES) - covered, set())

    def test_summary(self):
        # Printed so the test log carries the per-category counts.
        counts = Counter(cat or "allowed" for _c, _w, cat, _k in TABLE)
        sys.stderr.write("\ndecision table: %d rows\n" % len(TABLE))
        for cat, n in sorted(counts.items()):
            sys.stderr.write("  %-14s %d\n" % (cat, n))

    def test_messages_name_the_replacement(self):
        cases = {
            "git commit -m x": "bazel run //tools/git:commit",
            "git push": "bazel run //tools/git:push",
            "git rebase origin/main": "bazel run //tools/git:sync",
            "git worktree add ../x -b y": "bazel run //tools/worktree -- <branch>",
            "git worktree add --detach /tmp/x HEAD": "--detach <ref>",
            "git worktree lock ../x": "--lock",
            "git worktree prune": "--prune",
            "gh pr create": "bazel run //tools/agent-app -- pr-create",
            "gitleaks detect": "bazel run //tools/secret-scan",
            "actionlint": "bazel run //tools/ci:actionlint",
            "rm -rf ~/.cache/bazel": "bazel run //tools/bazel-cache:gc",
            "go test ./...": "bazel test",
            "prettier --write .": "bazel run //tools/format",
            "kubectl apply -f x.yaml": "//tools/gitops",
            "gh run rerun 1 --failed": "bazel run //tools/agent-app -- run-rerun <run-id>",
            "gh run cancel 1": "bazel run //tools/agent-app -- run-cancel <run-id>",
            "gh workflow run ci.yaml": "bazel run //tools/agent-app -- workflow-run <file.yaml>",
        }
        for command, needle in cases.items():
            msg = self.fx.run(command).message
            self.assertIn(needle, msg, command)
            self.assertIn("guardrail", msg, command)

    def test_merges_point_at_pr_enqueue(self):
        msg = self.fx.run("gh pr merge 3 --squash --auto").message
        self.assertIn("bazel run //tools/agent-app -- pr-enqueue", msg)
        # pr-enqueue exists: the advice must not call it unbuilt.
        self.assertNotIn("not in this checkout yet", msg)

    def test_message_says_when_there_is_no_target(self):
        msg = self.fx.run("git reset --hard HEAD~1").message
        self.assertIn("no target for it yet", msg)
        self.assertIn("James", msg)

    def test_run_commands_point_at_agent_app(self):
        # agent-app has run-rerun, run-cancel and workflow-run (wren only);
        # deleting runs and enabling or disabling workflows still have no target.
        for command in ("gh run rerun 1", "gh run cancel 1", "gh workflow run ci.yaml"):
            msg = self.fx.run(command).message
            self.assertIn("//tools/agent-app --", msg, command)
            self.assertIn("Only wren's App has Actions write", msg, command)
            self.assertNotIn("no target for it yet", msg, command)
        self.assertIn(
            "workflow-allowlist.txt", self.fx.run("gh workflow run ci.yaml").message
        )
        for command in (
            "gh run delete 1",
            "gh workflow enable ci.yaml",
            "gh workflow disable ci.yaml",
        ):
            msg = self.fx.run(command).message
            self.assertIn("no target for it yet", msg, command)
            self.assertIn(
                "nothing that deletes runs or enables or disables", msg, command
            )

    def test_pending_target_is_flagged_until_it_lands(self):
        msg = self.fx.run("git push").message
        self.assertIn("not in this checkout yet", msg)
        os.makedirs(os.path.join(self.fx.repo, "tools", "git"))
        with open(os.path.join(self.fx.repo, "tools", "git", "BUILD"), "w") as fh:
            fh.write('sh_binary(name = "push")\n')
        try:
            msg = self.fx.run("git push").message
            self.assertNotIn("not in this checkout yet", msg)
        finally:
            shutil.rmtree(os.path.join(self.fx.repo, "tools"))

    def test_merge_commit_points_at_concluding_merge(self):
        msg = self.fx.run("git commit", "merging").message
        self.assertIn("//tools/git:commit", msg)
        self.assertIn("concludes", msg)


class PendingTargetsTest(unittest.TestCase):
    """Every file a replacement target's `pending` names is in the repo and
    still holds the target. Otherwise every refusal naming it says the target
    "is not in this checkout yet" (it did for //tools/agent-app and
    //tools/worktree once their scripts were deleted). The files come from
    //tools/agent-guard:pending_target_files, so a deleted one fails the build."""

    def targets(self):
        return {
            name: value
            for name, value in vars(g).items()
            if name.startswith("T_") and isinstance(value, tuple) and len(value) == 2
        }

    def test_every_pending_file_exists_and_holds_its_target(self):
        problems = []
        targets = self.targets()
        self.assertGreater(len(targets), 10)
        for name, (use, pending) in sorted(targets.items()):
            if pending is None:
                continue
            rel, needle = pending
            if not os.path.isfile(rel):
                problems.append(
                    "%s names %s, which is missing (or not in :pending_target_files)"
                    % (name, rel)
                )
            elif needle is not None:
                with open(rel, encoding="utf-8") as fh:
                    if needle not in fh.read():
                        problems.append("%s: %s no longer has %r" % (name, rel, needle))
        self.assertEqual(problems, [])

    def test_existing_targets_are_not_called_pending(self):
        fx = Fixture()
        try:
            for command in (
                "gh pr create --title x",
                "gh pr merge 1 --auto",
                "gh run rerun 1",
                "gh run cancel 1",
                "gh workflow run ci.yaml",
                "git worktree add --detach /tmp/x HEAD",
                "git worktree lock ../x",
            ):
                with mock.patch.object(g, "installer_problem", return_value=""):
                    msg = fx.run(command).message
                self.assertNotIn("not in this checkout yet", msg, command)
                self.assertIn("//tools/", msg, command)
        finally:
            fx.close()


GIT_TEST_ENV = {
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@e",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@e",
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_NOSYSTEM": "1",
}


class InstallerSourceTest(unittest.TestCase):
    """An agent may run the installer only from a checkout where install.py,
    agent_guard.py and BUILD are origin/main's and no bazelrc sets run_under:
    an edited installer would otherwise run with James's HOME."""

    def setUp(self):
        self.tmp = os.path.realpath(
            tempfile.mkdtemp(
                prefix="agent-guard-installer-",
                dir="/tmp" if os.access("/tmp", os.W_OK) else None,
            )
        )
        self.repo = os.path.join(self.tmp, "vitruvian-core")
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home)
        files = {
            "MODULE.bazel": 'module(name = "vitruvian_core")\n',
            ".bazelrc": "try-import %workspace%/user.bazelrc\nbuild --jobs=4\n"
            "# run_under in a comment is fine\n",
            "tools/agent-guard/install.py": "print('installer')\n",
            "tools/agent-guard/agent_guard.py": "# guard\n",
            "tools/agent-guard/BUILD": 'py_binary(name = "install", main = "install.py")\n',
            "tools/agent-guard/src/lib.rs": "// guard\n",
            "tools/agent-guard/install/main.rs": "// installer\n",
        }
        for rel, text in files.items():
            self.write(rel, text)
        self.git("init", "-q", "-b", "main")
        self.git("add", "-A")
        self.git("commit", "-qm", "init", "--no-gpg-sign")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        g._scope_cache.clear()
        g._root_cache.clear()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)
        g._scope_cache.clear()
        g._root_cache.clear()

    def write(self, rel, text, root=None):
        path = os.path.join(root or self.repo, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as fh:
            fh.write(text)

    def git(self, *args, cwd=None):
        subprocess.run(
            ["git", "-C", cwd or self.repo] + list(args),
            env=dict(os.environ, **GIT_TEST_ENV),
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def decide(self, command, cwd=None):
        return g.evaluate(
            command,
            cwd or self.repo,
            home=self.home,
            git_state=lambda _d: g.GitState(),
        )

    COMMANDS = (
        "bazel run //tools/agent-guard:install",
        "bazel run //tools/agent-guard:install -- --check",
        "bazel run //tools/agent-guard:install -- --dry-run",
        "bazel run //tools/agent-guard:install -- --uninstall --dry-run",
        "python3 tools/agent-guard/install.py --check",
        "bazel-bin/tools/agent-guard/install --dry-run",
    )
    # The Rust installer, which must be held to the same rule.
    RS_COMMANDS = (
        "bazel run //tools/agent-guard:install_rs",
        "bazel run //tools/agent-guard:install_rs -- --check",
        "bazel run //tools/agent-guard:install_rs -- --uninstall --dry-run",
        "bazel-bin/tools/agent-guard/install_rs --dry-run",
    )

    def assert_all(self, want, cwd=None, needle="", commands=None):
        for command in commands or self.COMMANDS:
            d = self.decide(command, cwd)
            self.assertEqual(d.decision, want, "%s: %s" % (command, d.message))
            if want == D:
                self.assertEqual(d.category, "guard-config")
                self.assertIn(needle, d.message, command)

    def test_allowed_when_the_installer_is_origin_mains(self):
        self.assertEqual(g.installer_problem(self.repo, self.home), "")
        self.assert_all(A)

    def test_an_edited_install_py_is_refused(self):
        self.write("tools/agent-guard/install.py", "print('anything I like')\n")
        self.assert_all(
            D, needle="tools/agent-guard/install.py in %s differs" % self.repo
        )

    def test_an_edited_build_or_guard_is_refused(self):
        for rel in ("tools/agent-guard/BUILD", "tools/agent-guard/agent_guard.py"):
            self.write(rel, "# changed\n")
            self.assert_all(D, needle=rel)
            self.git("checkout", "--", rel)
        self.assert_all(A)

    def test_a_committed_but_unmerged_edit_is_refused(self):
        self.write("tools/agent-guard/install.py", "print('mine')\n")
        self.git("commit", "-qam", "mine", "--no-gpg-sign")
        self.assert_all(D, needle="differs from origin/main's")

    def test_an_edited_installer_in_a_worktree_is_refused_there_only(self):
        wt = os.path.join(self.tmp, "vitruvian-core-worktrees", "feat-x")
        self.git("worktree", "add", "-q", "--detach", wt)
        self.write("tools/agent-guard/install.py", "print('mine')\n", root=wt)
        self.assert_all(D, cwd=wt, needle="install.py in %s differs" % wt)
        self.assert_all(A)

    def test_no_origin_main_is_refused(self):
        self.git("update-ref", "-d", "refs/remotes/origin/main")
        self.assert_all(D, needle="origin/main or its installer cannot be read")

    def test_run_under_in_any_bazelrc_is_refused(self):
        self.write("user.bazelrc", "run --run_under='env -u CLAUDECODE'\n")
        self.assert_all(D, needle="user.bazelrc sets run_under")
        os.remove(os.path.join(self.repo, "user.bazelrc"))
        self.write(".bazelrc", "run --script_path=/tmp/x.sh\n", root=self.home)
        self.assert_all(D, needle=".bazelrc sets run_under or script_path")

    def test_outside_a_checkout_is_refused(self):
        d = self.decide("bazel run //tools/agent-guard:install", cwd=self.home)
        self.assertEqual(d.decision, D, d.message)
        self.assertIn("not run from inside a vitruvian-core checkout", d.message)

    # The Rust installer is built from every file under src/ and install/, so
    # each of those is held to origin/main too, and :install_rs is an installer.

    def test_an_edited_file_under_src_is_refused(self):
        rel = "tools/agent-guard/src/lib.rs"
        self.write(rel, "// anything I like\n")
        needle = "%s in %s differs" % (rel, self.repo)
        self.assert_all(D, needle=needle)
        self.assert_all(D, needle=needle, commands=self.RS_COMMANDS)
        self.git("checkout", "--", rel)
        self.assert_all(A)

    def test_an_added_file_under_install_is_refused(self):
        rel = "tools/agent-guard/install/extra.rs"
        self.write(rel, "// mine\n")
        needle = "%s in %s differs" % (rel, self.repo)
        self.assert_all(D, needle=needle)
        self.assert_all(D, needle=needle, commands=self.RS_COMMANDS)
        os.remove(os.path.join(self.repo, rel))
        self.assert_all(A)

    def test_install_rs_is_treated_like_install(self):
        self.assert_all(A, commands=self.RS_COMMANDS)
        self.write("tools/agent-guard/install.py", "print('mine')\n")
        self.assert_all(
            D,
            needle="tools/agent-guard/install.py in %s differs" % self.repo,
            commands=self.RS_COMMANDS,
        )
        d = self.decide("bazel run //tools/agent-guard:install_rs", cwd=self.home)
        self.assertEqual(d.decision, D, d.message)
        self.assertIn("not run from inside a vitruvian-core checkout", d.message)


class ScopeTest(unittest.TestCase):
    def setUp(self):
        self.fx = Fixture()

    def tearDown(self):
        self.fx.close()

    def test_oversize_outside_is_allowed(self):
        d = self.fx.run("true; " * 25000, "out")
        self.assertEqual(d.decision, "allow")

    def test_outside_vitruvian_core_is_allowed(self):
        for command in (
            "git push",
            "git commit -am x",
            "go test ./...",
            "pnpm install",
            "gh pr merge 1 --auto",
            "kubectl apply -f x",
        ):
            d = self.fx.run(command, "out")
            self.assertEqual(d.decision, "allow", command)
            self.assertEqual(d.scope, "outside", command)

    def test_other_bazel_repo_is_outside(self):
        other = os.path.join(self.fx.tmp, "abrialcode")
        os.makedirs(other)
        with open(os.path.join(other, "MODULE.bazel"), "w") as fh:
            fh.write('module(name = "abrialcode")\n')
        d = g.evaluate(
            "git push", other, home=self.fx.home, git_state=lambda _d: g.GitState()
        )
        self.assertEqual(d.decision, "allow")

    def test_worktree_and_subdirectory_are_inside(self):
        for cwd in (self.fx.wt, os.path.join(self.fx.repo, "src")):
            d = g.evaluate(
                "git push", cwd, home=self.fx.home, git_state=lambda _d: g.GitState()
            )
            self.assertEqual(d.decision, "deny", cwd)
            self.assertEqual(d.scope, "inside")

    def test_cd_out_of_the_repo_leaves_scope(self):
        d = self.fx.run("cd {out} && git push")
        self.assertEqual(d.decision, "allow")

    def test_inside_allowed_is_reported_inside(self):
        self.assertEqual(self.fx.run("git status").scope, "inside")

    def test_unknown_location_is_enforced(self):
        def run(command):
            return g.evaluate(
                command,
                g.UNKNOWN_CWD,
                home=self.fx.home,
                git_state=lambda _d: g.GitState(primary=True),
                cwd_known=False,
            )

        for command in ("go vet ./...", "git push", "cd /tmp && git commit -m x"):
            d = run(command)
            self.assertEqual((d.decision, d.scope), ("deny", "unknown"), command)
        self.assertEqual(run("true; " * 25000).decision, "deny")
        d = run("git status")
        self.assertEqual((d.decision, d.scope), ("allow", "unknown"))
        self.assertEqual(run("gh pr merge 1 -R someone/else").decision, "allow")


class ModesTest(unittest.TestCase):
    def setUp(self):
        self.fx = Fixture()

    def tearDown(self):
        self.fx.close()

    def test_enforce_warn_off(self):
        base = {c: "enforce" for c in g.CATEGORIES}
        self.assertEqual(self.fx.run("git push", modes=base).decision, "deny")
        warn = dict(base, **{"git-push": "warn"})
        d = self.fx.run("git push", modes=warn)
        self.assertEqual(d.decision, "warn")
        self.assertEqual(d.category, "git-push")
        off = dict(base, **{"git-push": "off"})
        self.assertEqual(self.fx.run("git push", modes=off).decision, "allow")

    def test_a_later_enforced_segment_beats_an_earlier_warning(self):
        modes = dict({c: "enforce" for c in g.CATEGORIES}, **{"git-commit": "warn"})
        d = self.fx.run("git commit -m x && git push", modes=modes)
        self.assertEqual((d.decision, d.category), ("deny", "git-push"))

    def test_policy_file(self):
        path = os.path.join(self.fx.tmp, "policy.json")
        with open(path, "w") as fh:
            json.dump(
                {
                    "default_mode": "warn",
                    "categories": {"go": {"mode": "off"}, "git-push": "enforce"},
                },
                fh,
            )
        modes = g.load_policy(path)
        self.assertEqual(modes["go"], "off")
        self.assertEqual(modes["git-push"], "enforce")
        self.assertEqual(modes["git-commit"], "warn")

    def test_broken_or_missing_policy_enforces_everything(self):
        path = os.path.join(self.fx.tmp, "broken.json")
        with open(path, "w") as fh:
            fh.write("{not json")
        for p in (path, os.path.join(self.fx.tmp, "missing.json")):
            self.assertEqual(set(g.load_policy(p).values()), {"enforce"})

    def test_shipped_policy_enforces_every_category(self):
        modes = g.load_policy(g.default_policy_path())
        self.assertEqual(set(modes), set(g.CATEGORIES))
        self.assertEqual(set(modes.values()), {"enforce"})
        with open(g.default_policy_path()) as fh:
            self.assertEqual(set(json.load(fh)["categories"]), set(g.CATEGORIES))


class PerformanceTest(unittest.TestCase):
    """The whole hook, end to end, must answer well inside its 10 s timeout.

    The command-tool entry fails closed, so a slow answer is a refusal. Each
    case runs main() on a full payload: parse, decide, redact and log.
    """

    LIMIT = 1.0

    @classmethod
    def setUpClass(cls):
        cls.fx = Fixture()
        cls._old = os.environ.get("AGENT_GUARD_HOME")
        os.environ["AGENT_GUARD_HOME"] = cls.fx.home

    @classmethod
    def tearDownClass(cls):
        if cls._old is None:
            os.environ.pop("AGENT_GUARD_HOME", None)
        else:
            os.environ["AGENT_GUARD_HOME"] = cls._old
        cls.fx.close()

    def timed(self, name, command, cwd=None):
        payload = json.dumps(
            {
                "tool_name": "Bash",
                "cwd": cwd or self.fx.repo,
                "tool_input": {"command": command},
            }
        )
        out = io.StringIO()
        start = time.perf_counter()
        g.main([], stdin=io.StringIO(payload), stdout=out)
        took = time.perf_counter() - start
        sys.stderr.write(
            "\nperf: %-34s %8.3f s (%d bytes)" % (name, took, len(command))
        )
        self.assertLess(took, self.LIMIT, name)
        text = out.getvalue().strip()
        return (
            json.loads(text)["hookSpecificOutput"].get("permissionDecision")
            if text
            else "allow"
        )

    def test_100kb_single_word(self):
        self.assertEqual(
            self.timed("100 KB single word", "echo " + "QUJD" * 25000), "allow"
        )

    def test_100kb_word_shaped_like_a_secret_name(self):
        # The pattern that backtracked: NAME_TOKEN followed by a long word.
        self.assertEqual(
            self.timed("100 KB X_TOKEN word", "echo X_TOKEN" + "a" * 100000 + "=v"),
            "allow",
        )

    def test_1mb_command(self):
        self.assertEqual(
            self.timed("1 MB single word", "echo " + "QUJD" * 262144), "allow"
        )
        blob = json.dumps({"k%d" % i: "v" * 20 for i in range(30000)})
        self.assertEqual(
            self.timed("1 MB JSON line", "echo '%s' | jq ." % blob), "allow"
        )
        self.assertEqual(
            self.timed(
                "1 MB of words then git push",
                "echo " + "word " * 200000 + "&& git push",
            ),
            "deny",
        )

    def test_5mb_heredoc(self):
        body = "a line with token=abc, it's `git push` and $(go test)\n" * 95000
        self.assertEqual(
            self.timed("5 MB quoted heredoc", "cat <<'EOF' > f\n" + body + "EOF"),
            "allow",
        )
        self.assertEqual(
            self.timed(
                "5 MB heredoc in $(cat)",
                "gh issue comment 1 --body \"$(cat <<'EOF'\n" + body + 'EOF\n)"',
            ),
            "allow",
        )
        self.assertEqual(
            self.timed(
                "5 MB unquoted heredoc",
                "cat <<EOF > f\n" + "line $x `date` it's\n" * 300000 + "EOF",
            ),
            "allow",
        )

    def test_too_many_commands_is_refused_quickly(self):
        self.assertEqual(self.timed("500k commands", "a;" * 500000), "deny")
        self.assertEqual(
            self.timed("500k commands, outside", "a;" * 500000, cwd=self.fx.out),
            "allow",
        )

    def test_adversarial_shapes(self):
        for name, cmd in (
            ("1M open parens", "(" * 1000000),
            ("300k $( unbalanced", "$(" * 300000),
            ("1M backslashes", "\\" * 1000000),
            ("1M double quotes", '"' * 1000000),
            ("500k && ", "&&" * 500000),
        ):
            self.timed(name, cmd)

    def test_log_line_is_bounded_and_redacted(self):
        secret = "ghp_" + "A" * 36
        self.timed("secret then 1 MB", "GH_TOKEN=%s echo %s" % (secret, "x" * 1000000))
        with open(g.log_path(self.fx.home)) as fh:
            rec = json.loads(fh.readlines()[-1])
        self.assertNotIn(secret, rec["command"])
        self.assertIn("[truncated, ", rec["command"])
        self.assertLess(len(rec["command"]), 1100)


class RedactionTest(unittest.TestCase):
    def test_redacts(self):
        cases = [
            ("mysql -phunter2 db", "hunter2"),
            ("psql postgres://app:s3cr3t@db:5432/x", "s3cr3t"),
            ("redis-cli -u redis://default:r3dispass@host:6379", "r3dispass"),
            ("curl -u admin:adm1npass https://x", "adm1npass"),  # gitleaks:allow
            ("curl --user admin:adm1npass https://x", "adm1npass"),  # gitleaks:allow
            ("gh secret set FOO --body s3cretvalue", "s3cretvalue"),
            ("gh secret set FOO -b 'two words'", "two words"),
            ('gh secret set FOO --body="quoted value" -R x/y', "quoted value"),
            ("curl -H 'X-Api-Key: k3yvalue' https://x", "k3yvalue"),
            (
                "curl -H 'X-Auth-Token: t0kenvalue' https://x",  # gitleaks:allow
                "t0kenvalue",
            ),
            ("curl -H 'PRIVATE-TOKEN: glvalue123' https://x", "glvalue123"),
            (
                "curl 'https://x?key=AIzaSyA1234567890abcdefghijklmnopqrstuv'",  # gitleaks:allow
                "AIzaSyA1234567890abcdefghijklmnopqrstuv",  # gitleaks:allow
            ),
            (
                "echo ghs_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123",
                "ghs_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123",
            ),
            (
                "echo github_pat_11ABCDEFG0123456789_abcdefghijklmnop",
                "github_pat_11ABCDEFG0123456789_abcdefghijklmnop",
            ),
            ("echo xoxb-1234567890-abcdefghij", "xoxb-1234567890-abcdefghij"),
            ("echo xoxp-1234567890-abcdefghij", "xoxp-1234567890-abcdefghij"),
            (
                "echo sk-ant-api03-abcdefghijklmnopqrstuvwxyz",
                "sk-ant-api03-abcdefghijklmnopqrstuvwxyz",
            ),
            ("tool --password=hunter2", "hunter2"),
            ("tool --password hunter2", "hunter2"),
            ("curl 'https://x/?token=abc123def'", "abc123def"),
            (
                "GH_TOKEN=ghs_abcdefghijklmnopqrstuvwxyz0123 gh pr list",
                "ghs_abcdefghijklmnopqrstuvwxyz0123",
            ),
            (
                "curl -H 'Authorization: Bearer sekrit-value-123' https://x",  # gitleaks:allow
                "sekrit-value-123",
            ),
            (
                'curl -H "Authorization: token abcdefgh12345" x',  # gitleaks:allow
                "abcdefgh12345",
            ),
            ("git clone https://user:pa55word@github.com/x/y", "pa55word"),
            (
                "echo ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
                "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
            ),
            ("API_KEY=xyz789 ./run", "xyz789"),
            ("vault login --token s.abcdef", "s.abcdef"),
        ]
        for text, secret in cases:
            out = g.redact(text)
            self.assertNotIn(secret, out, text)
            self.assertIn("[REDACTED]", out, text)

    def test_leaves_ordinary_commands_alone(self):
        for text in (
            "git log --oneline",
            "go test ./...",
            "gh pr view 12",
            "git log -p 5",
            "git log -p -5",
            "patch -p1 < x.diff",
            "git apply -p2 x.patch",
            "find . -print",
            "find . -path ./x -prune",
            "sudo -u james ls",
            "mkdir -p a/b",
            "gh secret list",
            "ssh -p 2222 host",
        ):
            self.assertEqual(g.redact(text), text)


class HookHarness(unittest.TestCase):
    """Runs main() on a payload with a private HOME and policy. No tests of its own."""

    def setUp(self):
        self.fx = Fixture()
        self.policy = os.path.join(self.fx.tmp, "policy.json")
        shutil.copy(g.default_policy_path(), self.policy)
        self.env = {"AGENT_GUARD_HOME": self.fx.home, "AGENT_GUARD_POLICY": self.policy}
        self._old = {k: os.environ.get(k) for k in self.env}
        os.environ.update(self.env)

    def tearDown(self):
        for k, v in self._old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.fx.close()

    def hook(self, payload):
        out = io.StringIO()
        rc = g.main([], stdin=io.StringIO(json.dumps(payload)), stdout=out)
        self.assertEqual(rc, 0)
        text = out.getvalue().strip()
        return json.loads(text) if text else None

    def log(self):
        with open(g.log_path(self.fx.home)) as fh:
            return [json.loads(line) for line in fh]


class HookIOTest(HookHarness):
    def test_deny_uses_the_pretooluse_protocol_and_logs(self):
        out = self.hook(
            {
                "tool_name": "Bash",
                "cwd": self.fx.repo,
                "session_id": "s1",
                "tool_input": {
                    "command": "GH_TOKEN=ghs_abcdefghijklmnopqrstuvwxyz0123 git push"
                },
            }
        )
        hso = out["hookSpecificOutput"]
        self.assertEqual(hso["hookEventName"], "PreToolUse")
        self.assertEqual(hso["permissionDecision"], "deny")
        self.assertIn("//tools/git:push", hso["permissionDecisionReason"])
        rec = self.log()[-1]
        self.assertEqual(
            (rec["decision"], rec["category"], rec["scope"]),
            ("deny", "git-push", "inside"),
        )
        self.assertNotIn("ghs_", rec["command"])
        for key in ("ts", "cwd", "category", "decision", "command"):
            self.assertIn(key, rec)

    def test_allow_prints_nothing_and_logs(self):
        self.assertIsNone(
            self.hook(
                {
                    "tool_name": "Bash",
                    "cwd": self.fx.repo,
                    "tool_input": {"command": "git status"},
                }
            )
        )
        self.assertEqual(self.log()[-1]["decision"], "allow")

    def test_outside_is_allowed_and_logged(self):
        self.assertIsNone(
            self.hook(
                {
                    "tool_name": "Bash",
                    "cwd": self.fx.out,
                    "tool_input": {"command": "git push"},
                }
            )
        )
        rec = self.log()[-1]
        self.assertEqual((rec["decision"], rec["scope"]), ("allow", "outside"))

    def test_long_commands_are_truncated(self):
        self.hook(
            {
                "tool_name": "Bash",
                "cwd": self.fx.repo,
                "tool_input": {"command": "echo " + "x" * 5000},
            }
        )
        self.assertLess(len(self.log()[-1]["command"]), 1100)

    def test_warn_mode_adds_context(self):
        with open(self.policy) as fh:
            p = json.load(fh)
        p["categories"]["git-push"]["mode"] = "warn"
        with open(self.policy, "w") as fh:
            json.dump(p, fh)
        out = self.hook(
            {
                "tool_name": "Bash",
                "cwd": self.fx.repo,
                "tool_input": {"command": "git push"},
            }
        )
        self.assertNotIn("permissionDecision", out["hookSpecificOutput"])
        self.assertIn("warn mode", out["hookSpecificOutput"]["additionalContext"])
        self.assertEqual(self.log()[-1]["decision"], "warn")

    def test_terminal_panel_uses_its_own_cwd(self):
        out = self.hook(
            {
                "tool_name": "mcp__terminal__run_in_terminal",
                "cwd": self.fx.out,
                "tool_input": {"command": "git push", "cwd": self.fx.repo},
            }
        )
        self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_monitor_and_desktop_commander(self):
        for tool, field in (
            ("Monitor", "command"),
            (
                "mcp__plugin_desktop-commander_desktop-commander__start_process",
                "command",
            ),
            (
                "mcp__plugin_desktop-commander_desktop-commander__interact_with_process",
                "input",
            ),
        ):
            out = self.hook(
                {
                    "tool_name": tool,
                    "cwd": self.fx.repo,
                    "tool_input": {field: "go test ./..."},
                }
            )
            self.assertEqual(
                out["hookSpecificOutput"]["permissionDecision"], "deny", tool
            )

    def test_auto_merge_tool(self):
        url = "https://github.com/VitruvianSoftware/vitruvian-core/pull/1"
        out = self.hook(
            {
                "tool_name": "mcp__ccd_pr__set_auto_merge",
                "cwd": self.fx.out,
                "tool_input": {"enabled": True, "url": url},
            }
        )
        self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertIsNone(
            self.hook(
                {
                    "tool_name": "mcp__ccd_pr__set_auto_merge",
                    "cwd": self.fx.out,
                    "tool_input": {"enabled": False, "url": url},
                }
            )
        )
        self.assertIsNone(
            self.hook(
                {
                    "tool_name": "mcp__ccd_pr__set_auto_merge",
                    "cwd": self.fx.out,
                    "tool_input": {
                        "enabled": True,
                        "url": "https://github.com/x/other/pull/1",
                    },
                }
            )
        )

    def test_kubernetes_mcp(self):
        out = self.hook(
            {
                "tool_name": "mcp__kubernetes__kubectl_apply",
                "cwd": self.fx.repo,
                "tool_input": {"manifest": "x"},
            }
        )
        self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny")
        out = self.hook(
            {
                "tool_name": "mcp__kubernetes__kubectl_generic",
                "cwd": self.fx.repo,
                "tool_input": {"command": "rollout", "subCommand": "restart"},
            }
        )
        self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertIsNone(
            self.hook(
                {
                    "tool_name": "mcp__kubernetes__kubectl_generic",
                    "cwd": self.fx.repo,
                    "tool_input": {"command": "get"},
                }
            )
        )
        self.assertIsNone(
            self.hook(
                {
                    "tool_name": "mcp__kubernetes__kubectl_rollout",
                    "cwd": self.fx.repo,
                    "tool_input": {"subCommand": "status"},
                }
            )
        )

    def test_log_is_private(self):
        self.hook(
            {
                "tool_name": "Bash",
                "cwd": self.fx.repo,
                "tool_input": {"command": "git status"},
            }
        )
        path = g.log_path(self.fx.home)
        self.assertEqual(os.stat(os.path.dirname(path)).st_mode & 0o777, 0o700)
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
        # An existing loose directory and file are tightened.
        os.chmod(os.path.dirname(path), 0o755)
        os.chmod(path, 0o644)
        self.hook(
            {
                "tool_name": "Bash",
                "cwd": self.fx.repo,
                "tool_input": {"command": "git status"},
            }
        )
        self.assertEqual(os.stat(os.path.dirname(path)).st_mode & 0o777, 0o700)
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)

    def test_desktop_commander_cannot_touch_the_session_start_scripts(self):
        dc = "mcp__plugin_desktop-commander_desktop-commander__"
        for rel in ("tools/remote/setup.sh",):
            path = os.path.join(self.fx.repo, rel)
            for tool, tin in (
                ("write_file", {"path": path, "content": "exit 0"}),
                (
                    "edit_block",
                    {"file_path": path, "old_string": "a", "new_string": "b"},
                ),
                ("move_file", {"source": path, "destination": "/tmp/x"}),
                ("move_file", {"source": "/tmp/x", "destination": path}),
            ):
                out = self.hook(
                    {"tool_name": dc + tool, "cwd": self.fx.repo, "tool_input": tin}
                )
                self.assertEqual(
                    out["hookSpecificOutput"]["permissionDecision"], "deny", (tool, rel)
                )
                self.assertEqual(self.log()[-1]["category"], "guard-config")
            # A shell write through Desktop Commander's process tools too.
            out = self.hook(
                {
                    "tool_name": dc + "start_process",
                    "cwd": self.fx.repo,
                    "tool_input": {"command": "echo 'exit 0' > " + path},
                }
            )
            self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_desktop_commander_file_tools_cannot_touch_the_guard(self):
        dc = "mcp__plugin_desktop-commander_desktop-commander__"
        guard = os.path.join(self.fx.home, ".local/share/agent-guard")
        for tool, tin in (
            ("write_file", {"path": guard + "/policy.json", "content": "{}"}),
            (
                "edit_block",
                {
                    "file_path": guard + "/agent_guard.py",
                    "old_string": "a",
                    "new_string": "b",
                },
            ),
            ("move_file", {"source": "/tmp/x", "destination": guard + "/hook.py"}),
            ("move_file", {"source": guard + "/hook.py", "destination": "/tmp/x"}),
            ("create_directory", {"path": guard + "/sub"}),
            (
                "write_pdf",
                {"path": "/tmp/a.pdf", "content": "x", "outputPath": guard + "/x.pdf"},
            ),
        ):
            out = self.hook(
                {"tool_name": dc + tool, "cwd": self.fx.out, "tool_input": tin}
            )
            self.assertEqual(
                out["hookSpecificOutput"]["permissionDecision"], "deny", tool
            )
        self.assertIsNone(
            self.hook(
                {
                    "tool_name": dc + "write_file",
                    "cwd": self.fx.repo,
                    "tool_input": {
                        "path": os.path.join(self.fx.repo, "x.txt"),
                        "content": "x",
                    },
                }
            )
        )

    def test_file_tools_cannot_edit_the_installed_guard(self):
        target = os.path.join(self.fx.home, ".local/share/agent-guard/policy.json")
        out = self.hook(
            {
                "tool_name": "Write",
                "cwd": self.fx.out,
                "tool_input": {"file_path": target, "content": "{}"},
            }
        )
        self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertIsNone(
            self.hook(
                {
                    "tool_name": "Edit",
                    "cwd": self.fx.repo,
                    "tool_input": {
                        "file_path": os.path.join(
                            self.fx.repo, "tools/agent-guard/policy.json"
                        )
                    },
                }
            )
        )

    def test_file_tools_cannot_touch_the_hook_files(self):
        for tool in ("Write", "Edit", "MultiEdit"):
            for rel in (
                ".claude/settings.json",
                ".claude/settings.local.json",
                ".claude/block-queue-bypass.sh",
                ".claude/session-start.sh",
                ".agents/hooks.json",
                "tools/agent-guard/hook.sh",
                "tools/remote/setup.sh",
            ):
                for root in (self.fx.repo, self.fx.wt):
                    out = self.hook(
                        {
                            "tool_name": tool,
                            "cwd": root,
                            "tool_input": {"file_path": os.path.join(root, rel)},
                        }
                    )
                    self.assertEqual(
                        out["hookSpecificOutput"]["permissionDecision"],
                        "deny",
                        (tool, rel),
                    )
            # Relative paths count too, and the log names the file.
            out = self.hook(
                {
                    "tool_name": tool,
                    "cwd": self.fx.repo,
                    "tool_input": {"file_path": ".agents/hooks.json"},
                }
            )
            self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny")
            self.assertEqual(self.log()[-1]["category"], "guard-config")
        # The guard's source and policy are fine to edit: they only take
        # effect once merged, because hook.sh runs origin/main's copy.
        for rel in (
            "tools/agent-guard/agent_guard.py",
            "tools/agent-guard/policy.json",
            ".claude/notes.md",
            "tools/cloud-bootstrap/cloud-bootstrap_test.sh",
            "tools/cloud-bootstrap/README.md",
            "tools/remote/setup_test.sh",
        ):
            self.assertIsNone(
                self.hook(
                    {
                        "tool_name": "Edit",
                        "cwd": self.fx.repo,
                        "tool_input": {"file_path": os.path.join(self.fx.repo, rel)},
                    }
                ),
                rel,
            )
        # Outside a vitruvian-core checkout the same names are someone else's.
        self.assertIsNone(
            self.hook(
                {
                    "tool_name": "Write",
                    "cwd": self.fx.out,
                    "tool_input": {
                        "file_path": os.path.join(self.fx.out, ".claude/settings.json")
                    },
                }
            )
        )

    def test_log_records_which_copy_decided(self):
        os.environ["AGENT_GUARD_SOURCE"] = "origin/main:abc"
        try:
            self.hook(
                {
                    "tool_name": "Bash",
                    "cwd": self.fx.repo,
                    "tool_input": {"command": "git status"},
                }
            )
        finally:
            del os.environ["AGENT_GUARD_SOURCE"]
        self.assertEqual(self.log()[-1]["source"], "origin/main:abc")
        self.hook(
            {
                "tool_name": "Bash",
                "cwd": self.fx.repo,
                "tool_input": {"command": "git status"},
            }
        )
        self.assertEqual(self.log()[-1]["source"], "")

    def test_antigravity_format(self):
        out = self.hook(
            {
                "toolCall": {
                    "name": "run_command",
                    "args": {"CommandLine": "git stash", "Cwd": self.fx.repo},
                }
            }
        )
        self.assertEqual(out["decision"], "deny")
        self.assertIn("stash", out["reason"])
        self.assertIsNone(
            self.hook(
                {
                    "toolCall": {
                        "name": "run_command",
                        "args": {"CommandLine": "git status", "Cwd": self.fx.repo},
                    }
                }
            )
        )
        self.assertEqual(self.log()[-1]["agent"], "antigravity")

    def test_garbage_input_is_allowed(self):
        out = io.StringIO()
        self.assertEqual(g.main([], stdin=io.StringIO("not json"), stdout=out), 0)
        self.assertEqual(out.getvalue(), "")


def agy_payload(command, cwd=None, workspace=None, tool="run_command", args=None):
    """The PreToolUse payload agy 1.4.0 sends, captured live (paths faked).

    No top-level cwd and no session_id: the directory is args.Cwd and the
    session is conversationId. The hook itself runs in ~/.gemini/config.
    """
    a = {
        "CommandLine": command,
        "Cwd": cwd,
        "WaitMsBeforeAsync": 5000,
        "toolAction": "Running command",
        "toolSummary": "Run a command",
    }
    if tool != "run_command":
        a = {"toolAction": "Doing it", "toolSummary": "Do it"}
    a.update(args or {})
    if cwd is None:
        a.pop("Cwd", None)
    p = {
        "toolCall": {"name": tool, "args": a},
        "stepIdx": 3,
        "conversationId": "0f6c1d2e-3a4b-4c5d-8e9f-a0b1c2d3e4f5",
        "transcriptPath": "/fake/home/.gemini/antigravity-cli/brain/x/transcript.jsonl",
        "artifactDirectoryPath": "/fake/home/.gemini/antigravity-cli/brain/x",
        "modelName": "auto",
    }
    if workspace is not None:
        p["workspacePaths"] = workspace
    return p


BACKSTOP_CMD = "/bin/sh -c 'h=...' agent-guard-backstop /Users/j/vitruvian-core"
USER_SETTINGS: Dict[str, Any] = {
    "effortLevel": "high",
    "hooks": {
        "PreToolUse": [
            {
                "matcher": "^(Bash)$",
                "hooks": [
                    {"type": "command", "command": BACKSTOP_CMD, "onFailure": "block"}
                ],
            },
            {
                "matcher": "^(Edit)$",
                "hooks": [{"type": "command", "command": BACKSTOP_CMD}],
            },
        ],
        "Stop": [{"hooks": [{"type": "command", "command": "/h/stop.sh"}]}],
    },
}
USER_GEMINI: Dict[str, Any] = {
    "agent-guard": {
        "enabled": True,
        "PreToolUse": [
            {
                "matcher": "run_command",
                "hooks": [{"type": "command", "command": BACKSTOP_CMD}],
            }
        ],
    },
    "response-contract": {"enabled": True, "PreInvocation": []},
}


class UserFileToolTest(HookHarness):
    """The backstop's user files: other settings may change through Claude
    Code's Edit, MultiEdit and Write; agent-guard's entries and
    disableAllHooks may not; other tools may not write them at all."""

    def setUp(self):
        super().setUp()
        self.settings = os.path.join(self.fx.home, ".claude", "settings.json")
        self.gemini = os.path.join(self.fx.home, ".gemini", "config", "hooks.json")
        for path, data in ((self.settings, USER_SETTINGS), (self.gemini, USER_GEMINI)):
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as fh:
                json.dump(data, fh, indent=2)
        with open(self.settings) as fh:
            self.text = fh.read()
        with open(self.gemini) as fh:
            self.gtext = fh.read()

    def decide(self, tool, tin):
        out = self.hook({"tool_name": tool, "cwd": self.fx.out, "tool_input": tin})
        return out["hookSpecificOutput"]["permissionDecision"] if out else "allow"

    def edit(self, old, new, path=None, **kw):
        return self.decide(
            "Edit",
            dict(file_path=path or self.settings, old_string=old, new_string=new, **kw),
        )

    def test_edits_to_other_settings_are_allowed(self):
        self.assertEqual(self.edit('"effortLevel": "high"', '"effortLevel": "low"'), A)
        self.assertEqual(self.edit('"/h/stop.sh"', '"/h/stop2.sh"'), A)
        self.assertEqual(
            self.edit(
                '"response-contract": {',
                '"other": {}, "response-contract": {',
                self.gemini,
            ),
            A,
        )
        self.assertEqual(
            self.decide(
                "MultiEdit",
                {
                    "file_path": self.settings,
                    "edits": [
                        {"old_string": '"high"', "new_string": '"max"'},
                        {"old_string": "/h/stop.sh", "new_string": "/h/s.sh"},
                    ],
                },
            ),
            A,
        )

    def test_edits_that_remove_or_change_agent_guard_entries_are_refused(self):
        self.assertEqual(self.edit('"onFailure": "block"', '"onFailure": "allow"'), D)
        self.assertEqual(
            self.edit("agent-guard-backstop", "nothing", replace_all=True), D
        )
        self.assertEqual(
            self.edit('"matcher": "^(Bash)$"', '"matcher": "^(Nothing)$"'), D
        )
        self.assertEqual(
            self.edit(
                '"enabled": true,\n    "PreToolUse"',
                '"enabled": false,\n    "PreToolUse"',
                self.gemini,
            ),
            D,
        )
        self.assertEqual(
            self.decide(
                "MultiEdit",
                {
                    "file_path": self.settings,
                    "edits": [
                        {"old_string": '"high"', "new_string": '"max"'},
                        {"old_string": '"onFailure": "block"', "new_string": '"x": 1'},
                    ],
                },
            ),
            D,
        )
        # Not found in the file (so it cannot be simulated) but aimed at our entries.
        self.assertEqual(self.edit("tools/agent-guard/hook.sh gone", "x"), D)

    def test_disable_all_hooks_true_is_refused_false_is_fine(self):
        self.assertEqual(
            self.edit(
                '"effortLevel": "high"',
                '"effortLevel": "high", "disableAllHooks": true',
            ),
            D,
        )
        self.assertEqual(
            self.edit(
                '"effortLevel": "high"', '"disableAllHooks":true,"effortLevel": "high"'
            ),
            D,
        )
        self.assertEqual(
            self.edit(
                '"effortLevel": "high"',
                '"disableAllHooks": false, "effortLevel": "high"',
            ),
            A,
        )
        data = dict(USER_SETTINGS, disableAllHooks=True)
        self.assertEqual(
            self.decide(
                "Write", {"file_path": self.settings, "content": json.dumps(data)}
            ),
            D,
        )
        data = dict(USER_SETTINGS, disableAllHooks=False)
        self.assertEqual(
            self.decide(
                "Write", {"file_path": self.settings, "content": json.dumps(data)}
            ),
            A,
        )
        # Flipping an existing false to true with an edit that names only the value.
        with open(self.settings, "w") as fh:
            json.dump(dict(USER_SETTINGS, disableAllHooks=False), fh, indent=2)
        self.assertEqual(self.edit("false", "true"), D)
        self.assertEqual(self.edit("false", "false "), A)

    def test_write_must_keep_the_same_entries(self):
        kept = dict(USER_SETTINGS, effortLevel="low", model="x")
        self.assertEqual(
            self.decide(
                "Write",
                {"file_path": self.settings, "content": json.dumps(kept, indent=4)},
            ),
            A,
        )
        dropped = dict(USER_SETTINGS, hooks={"Stop": USER_SETTINGS["hooks"]["Stop"]})
        for content in (json.dumps(dropped), "{}", "{not json"):
            self.assertEqual(
                self.decide("Write", {"file_path": self.settings, "content": content}),
                D,
                content,
            )
        g2 = {k: v for k, v in USER_GEMINI.items() if k != "agent-guard"}
        self.assertEqual(
            self.decide("Write", {"file_path": self.gemini, "content": json.dumps(g2)}),
            D,
        )
        self.assertEqual(
            self.decide(
                "Write",
                {
                    "file_path": self.gemini,
                    "content": json.dumps(dict(USER_GEMINI, extra={})),
                },
            ),
            A,
        )

    def test_write_with_no_entries_to_keep_is_allowed(self):
        os.remove(self.settings)
        self.assertEqual(
            self.decide("Write", {"file_path": self.settings, "content": '{"a": 1}'}), A
        )
        self.assertEqual(
            self.decide(
                "Write",
                {"file_path": self.settings, "content": '{"disableAllHooks": true}'},
            ),
            D,
        )

    def test_other_tools_may_not_write_them(self):
        for tool, tin in (
            (g.DC + "write_file", {"path": self.settings, "content": self.text}),
            (
                g.DC + "edit_block",
                {"file_path": self.gemini, "old_string": "a", "new_string": "b"},
            ),
            (g.DC + "move_file", {"source": self.settings, "destination": "/tmp/x"}),
            (g.DC + "move_file", {"source": "/tmp/x", "destination": self.gemini}),
            (
                g.DC + "move_file",
                {"source": os.path.dirname(self.settings), "destination": "/tmp/x"},
            ),
        ):
            self.assertEqual(self.decide(tool, tin), D, tool)
        out = self.hook(
            {
                "toolCall": {
                    "name": "write_to_file",
                    "args": {"TargetFile": self.gemini, "CodeContent": "{}"},
                },
                "workspacePaths": [self.fx.out],
            }
        )
        self.assertEqual(out["decision"], "deny")

    def test_the_refusal_says_what_to_do(self):
        out = self.hook(
            {
                "tool_name": "Edit",
                "cwd": self.fx.out,
                "tool_input": {
                    "file_path": self.settings,
                    "old_string": '"onFailure": "block"',
                    "new_string": '"onFailure": "allow"',
                },
            }
        )
        msg = out["hookSpecificOutput"]["permissionDecisionReason"]
        self.assertIn("removes or changes agent-guard's entries", msg)
        self.assertIn("bazel run //tools/agent-guard:install", msg)
        self.assertEqual(self.log()[-1]["category"], "guard-config")


class AntigravityHookTest(HookHarness):
    """agy's hook format end to end: decision JSON, location, the log."""

    def tearDown(self):
        os.chdir(self._cwd)
        super().tearDown()

    def setUp(self):
        super().setUp()
        # agy runs hooks in the folder holding hooks.json, outside any repo.
        self._cwd = os.getcwd()
        self.gemini_config = os.path.join(self.fx.home, ".gemini", "config")
        os.makedirs(self.gemini_config)
        os.chdir(self.gemini_config)

    def test_real_payload_go_vet_is_denied(self):
        out = self.hook(agy_payload("go vet ./...", self.fx.repo, [self.fx.repo]))
        self.assertEqual(set(out), {"decision", "reason"})
        self.assertEqual(out["decision"], "deny")
        self.assertIn("bazel test", out["reason"])

    def test_real_payload_git_status_prints_nothing(self):
        self.assertIsNone(
            self.hook(agy_payload("git status", self.fx.repo, [self.fx.repo]))
        )
        self.assertEqual(self.log()[-1]["decision"], "allow")

    def test_log_names_the_directory_and_the_conversation(self):
        self.hook(agy_payload("go vet ./...", self.fx.repo, [self.fx.repo]))
        rec = self.log()[-1]
        self.assertEqual(rec["agent"], "antigravity")
        self.assertEqual(rec["tool"], "run_command")
        self.assertEqual(rec["cwd"], self.fx.repo)
        self.assertEqual(rec["session"], "0f6c1d2e-3a4b-4c5d-8e9f-a0b1c2d3e4f5")
        self.assertEqual((rec["scope"], rec["decision"]), ("inside", "deny"))

    def test_missing_cwd_falls_back_to_the_workspaces(self):
        # Without the fallback the guard would judge ~/.gemini/config and allow.
        out = self.hook(agy_payload("go vet ./...", None, [self.fx.repo, self.fx.out]))
        self.assertEqual(out["decision"], "deny")
        self.assertEqual(self.log()[-1]["cwd"], self.fx.repo)
        # Any workspace inside vitruvian-core puts the call inside, not just the first.
        out = self.hook(agy_payload("git push", None, ["/tmp", self.fx.repo]))
        self.assertEqual(out["decision"], "deny")
        self.assertIn("//tools/git:push", out["reason"])
        self.assertEqual(self.log()[-1]["cwd"], self.fx.repo)
        # No workspace inside: the first one decides.
        self.assertIsNone(
            self.hook(agy_payload("go vet ./...", None, [self.fx.out, "/tmp"]))
        )
        rec = self.log()[-1]
        self.assertEqual((rec["scope"], rec["cwd"]), ("outside", self.fx.out))

    def test_cwd_wins_over_workspace_paths(self):
        self.assertIsNone(
            self.hook(agy_payload("go vet ./...", self.fx.out, [self.fx.repo]))
        )
        out = self.hook(agy_payload("go vet ./...", self.fx.repo, [self.fx.out]))
        self.assertEqual(out["decision"], "deny")

    def test_no_location_at_all_is_enforced(self):
        for workspace in (None, [], [""]):
            out = self.hook(agy_payload("go vet ./...", None, workspace))
            self.assertEqual(out["decision"], "deny", workspace)
            rec = self.log()[-1]
            self.assertEqual((rec["scope"], rec["cwd"]), ("unknown", ""), workspace)
        # Read-only commands still pass, and a gh call naming another repo is
        # still out of scope.
        self.assertIsNone(self.hook(agy_payload("git status", None)))
        self.assertIsNone(self.hook(agy_payload("gh pr merge 1 -R someone/else", None)))

    def test_a_relative_cwd_is_unknown_not_the_hooks_folder(self):
        out = self.hook(agy_payload("go vet ./...", "some/dir"))
        self.assertEqual(out["decision"], "deny")
        self.assertEqual(self.log()[-1]["scope"], "unknown")

    def test_other_command_tools(self):
        cases = (
            ("shell_exec", {"Command": "go test ./..."}),
            ("shell_exec", {"command": "go test ./..."}),
            ("send_command_input", {"Input": "go test ./...", "CommandId": "c1"}),
            (
                "manage_task",
                {"Action": "send_input", "TaskId": "t1", "Input": "go test ./..."},
            ),
        )
        for tool, args in cases:
            out = self.hook(
                agy_payload(None, None, [self.fx.repo], tool=tool, args=args)
            )
            self.assertEqual(out["decision"], "deny", (tool, args))
            self.assertEqual(self.log()[-1]["category"], "go", tool)
            self.assertIsNone(
                self.hook(agy_payload(None, None, [self.fx.out], tool=tool, args=args)),
                tool,
            )
        before = len(self.log())
        self.assertIsNone(
            self.hook(
                agy_payload(
                    None,
                    None,
                    [self.fx.repo],
                    tool="manage_task",
                    args={"Action": "kill", "TaskId": "t1"},
                )
            )
        )
        self.assertEqual(len(self.log()), before)

    def test_manage_task_send_input_as_captured(self):
        # Captured live from agy 1.4.2 on 2026-10-17 (paths and ids faked): the
        # model started `cat` with run_command, then sent it a line. No Cwd, so
        # the workspace paths say where it runs.
        payload = {
            "toolCall": {
                "name": "manage_task",
                "args": {
                    "Action": "send_input",
                    "Input": "hello cat\n",
                    "TaskId": "task-3",
                    "toolAction": "Sending input to background cat process",
                    "toolSummary": "Send input to cat",
                },
            },
            "stepIdx": 2,
            "conversationId": "0f6c1d2e-3a4b-4c5d-8e9f-a0b1c2d3e4f5",
            "transcriptPath": "/fake/home/.gemini/antigravity-cli/brain/x/transcript.jsonl",
            "artifactDirectoryPath": "/fake/home/.gemini/antigravity-cli/brain/x",
            "modelName": "auto",
            "workspacePaths": [self.fx.repo],
        }
        self.assertIsNone(self.hook(payload))
        payload["toolCall"]["args"]["Input"] = "git push\n"
        out = self.hook(payload)
        self.assertEqual(out["decision"], "deny")
        self.assertIn("//tools/git:push", out["reason"])

    def test_git_commit_tool_is_a_commit(self):
        args = {"CommitMessage": "fix things"}
        out = self.hook(
            agy_payload(None, None, [self.fx.repo], tool="git_commit", args=args)
        )
        self.assertEqual(out["decision"], "deny")
        self.assertIn("//tools/git:commit", out["reason"])
        rec = self.log()[-1]
        self.assertEqual((rec["category"], rec["tool"]), ("git-commit", "git_commit"))
        self.assertIn("fix things", rec["command"])
        self.assertIsNone(
            self.hook(
                agy_payload(None, None, [self.fx.out], tool="git_commit", args=args)
            )
        )
        out = self.hook(agy_payload(None, None, None, tool="git_commit", args=args))
        self.assertEqual(out["decision"], "deny")
        self.assertEqual(self.log()[-1]["scope"], "unknown")

    def test_file_tools_cannot_touch_the_guard(self):
        guard = os.path.join(self.fx.home, ".local/share/agent-guard/policy.json")
        mine = os.path.join(self.fx.repo, "src", "main.go")
        for tool, field in (
            ("write_to_file", "TargetFile"),
            ("replace_file_content", "TargetFile"),
            ("multi_replace_file_content", "TargetFile"),
            ("notebook_edit", "NotebookPath"),
        ):
            out = self.hook(
                agy_payload(None, None, [self.fx.repo], tool=tool, args={field: guard})
            )
            self.assertEqual(out["decision"], "deny", tool)
            self.assertEqual(self.log()[-1]["category"], "guard-config", tool)
            self.assertIsNone(
                self.hook(
                    agy_payload(
                        None, None, [self.fx.repo], tool=tool, args={field: mine}
                    )
                ),
                tool,
            )

    def test_file_tools_cannot_touch_the_hook_files(self):
        for rel in (
            ".agents/hooks.json",
            ".claude/settings.json",
            "tools/agent-guard/hook.sh",
            "tools/remote/setup.sh",
        ):
            path = os.path.join(self.fx.repo, rel)
            out = self.hook(
                agy_payload(
                    None,
                    None,
                    [self.fx.repo],
                    tool="write_to_file",
                    args={"TargetFile": path},
                )
            )
            self.assertEqual(out["decision"], "deny", rel)
            self.assertIn("James's call", out["reason"])
        # And through agy's shell, wherever the command says it runs.
        out = self.hook(
            agy_payload(
                "sed -i '' s/a/b/ tools/remote/setup.sh", self.fx.repo, [self.fx.repo]
            )
        )
        self.assertEqual(out["decision"], "deny")
        self.assertIn("session start", out["reason"])

    def test_warn_mode_prints_nothing(self):
        with open(self.policy) as fh:
            p = json.load(fh)
        p["categories"]["go"]["mode"] = "warn"
        with open(self.policy, "w") as fh:
            json.dump(p, fh)
        self.assertIsNone(self.hook(agy_payload("go vet ./...", self.fx.repo)))
        self.assertEqual(self.log()[-1]["decision"], "warn")


class ParserTest(unittest.TestCase):
    def words(self, text):
        return [c.words for c in g.parse_script(text)]

    def test_quotes_and_operators(self):
        self.assertEqual(
            self.words("a 'b c' \"d $e\" && f|g; h"),
            [["a", "b c", "d $e"], ["f"], ["g"], ["h"]],
        )

    def test_redirections_are_not_arguments(self):
        cmds = g.parse_script("git log > out.txt 2>&1 < /dev/null")
        self.assertEqual(cmds[0].words, ["git", "log"])
        self.assertIn((">", "out.txt"), cmds[0].redirects)

    def test_heredoc_body_is_data(self):
        cmds = g.parse_script("cat <<'EOF' > f\ngit push\nEOF\necho done")
        self.assertEqual([c.words for c in cmds], [["cat"], ["echo", "done"]])
        self.assertEqual(cmds[0].heredocs, ["git push"])

    def test_nested_substitution(self):
        self.assertIn(["git", "push"], self.words('echo "$(echo $(git push))"'))

    def test_heredoc_inside_substitution_is_skipped(self):
        text = "echo \"$(cat <<'EOF'\nit's `git push`\nEOF\n)\" && ls"
        self.assertEqual(
            self.words(text),
            [["echo", "$(cat <<'EOF'\nit's `git push`\nEOF\n)"], ["ls"], ["cat"]],
        )

    def test_fallback_drops_heredoc_bodies(self):
        text = "cat <<'EOF'\ndon't git push\nEOF\necho \"unterminated"
        self.assertNotIn("push", g.strip_heredoc_bodies(text))
        words = [w for c in g.fallback_split(text) for w in c.words]
        self.assertNotIn("push", words)

    def test_unquoted_heredoc_runs_its_substitutions(self):
        self.assertEqual(
            g.body_substitutions("a $(git push) `go test` \\$(no) \\`no\\` $((1+2))"),
            ["git push", "go test"],
        )
        self.assertIn(["git", "push"], self.words("cat <<EOF\n$(git push)\nEOF"))
        self.assertNotIn(["git", "push"], self.words("cat <<'EOF'\n$(git push)\nEOF"))

    def test_comments(self):
        self.assertEqual(self.words("ls # git push"), [["ls"]])


@unittest.skipUnless(shutil.which("git"), "git is not on PATH")
class RealGitStateTest(unittest.TestCase):
    """probe_git_state against a real repository with a real merge conflict."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="agent-guard-git-")
        self.env = dict(
            os.environ,
            GIT_AUTHOR_NAME="t",
            GIT_AUTHOR_EMAIL="t@e",
            GIT_COMMITTER_NAME="t",
            GIT_COMMITTER_EMAIL="t@e",
            GIT_CONFIG_GLOBAL="/dev/null",
            GIT_CONFIG_NOSYSTEM="1",
        )

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def git(self, *args, check=True):
        return subprocess.run(
            ["git", "-C", self.tmp] + list(args),
            env=self.env,
            check=check,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def test_conflict_is_seen(self):
        self.git("init", "-q", "-b", "main")
        path = os.path.join(self.tmp, "f.txt")
        with open(path, "w") as fh:
            fh.write("base\n")
        self.git("add", "f.txt")
        self.git("commit", "-qm", "base")
        self.git("checkout", "-qb", "side")
        with open(path, "w") as fh:
            fh.write("side\n")
        self.git("commit", "-qam", "side")
        self.git("checkout", "-q", "main")
        with open(path, "w") as fh:
            fh.write("main\n")
        self.git("commit", "-qam", "main")
        st = g.probe_git_state(self.tmp)
        self.assertFalse(st.in_progress)
        self.assertTrue(st.primary)
        self.git("merge", "side", check=False)
        st = g.probe_git_state(self.tmp)
        self.assertTrue(st.merge)
        self.assertEqual(st.unmerged, [os.path.realpath(path)])
        sys.stderr.write(
            "\nreal git: merge in progress detected, conflicted file %s\n"
            % st.unmerged[0]
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
