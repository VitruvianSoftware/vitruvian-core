#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

"""Tests for upstream.py, against throwaway upstream and monorepo repositories.

bazel test //apps/desktop/vitruvian:upstream_test
"""

import contextlib
import importlib.util
import io
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "upstream", Path(__file__).with_name("upstream.py")
)
upstream = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(upstream)

APP = upstream.APP_DIR
HEADER = (
    "// SPDX-License-Identifier: GPL-3.0-or-later\n// Copyright (C) 2026 Vorssaint\n\n"
)
# Enough shared lines for git to see the fork's copy as a rename (>= 50% similar).
BODY = "".join(f"// unchanged line {n}\n" for n in range(20))
FOO_UPSTREAM = (
    HEADER
    + BODY
    + (
        'let bundleID = "com.vorssaint.utils"\n'
        "func alpha() -> Int { 1 }\n"
        "\n"
        "func beta() -> Int { 2 }\n"
        "\n"
        "func gamma() -> Int { 3 }\n"
    )
)
# The fork's copy: rebranded, alpha rewritten by "the refactor", beta made `package`.
FOO_FORK = (
    HEADER
    + BODY
    + (
        'let bundleID = "com.vitruviansoftware.vitruvian"\n'
        "func alpha() -> Int { 100 }\n"
        "\n"
        "package func beta() -> Int { 2 }\n"
        "\n"
        "func gamma() -> Int { 3 }\n"
    )
)


def run(cwd, *args, env=None):
    return subprocess.run(
        ["git", *args], cwd=cwd, check=True, capture_output=True, text=True, env=env
    ).stdout.strip()


def write(root, rel, text):
    path = Path(root) / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def commit(root, message, env=None):
    run(root, "add", "-A")
    run(root, "commit", "-q", "-m", message, env=env)
    return run(root, "rev-parse", "HEAD")


class Fixture:
    """An upstream with commits B..G after base A, and a monorepo that imported A."""

    def __init__(self, tmp):
        self.tmp = Path(tmp)
        self.up = self.tmp / "upstream"
        self.mono = self.tmp / "mono"
        self.cache = self.tmp / "cache"
        for repo in (self.up, self.mono):
            repo.mkdir()
            run(repo, "init", "-q", "-b", "main")
        up = self.up
        write(up, "Sources/Vorssaint/Core/Foo.swift", FOO_UPSTREAM)
        write(up, "README.md", "upstream readme\n")
        write(up, ".github/ci.yml", "on: push\n")
        self.a = commit(up, "base")
        self.a_tree = run(up, "rev-parse", "HEAD^{tree}")

        write(self.mono, f"{APP}/Sources/Vorssaint/Core/Foo.swift", FOO_UPSTREAM)
        write(self.mono, f"{APP}/README.md", "upstream readme\n")
        self.import_commit = commit(self.mono, "import")
        run(self.mono, "mv", f"{APP}/Sources/Vorssaint", f"{APP}/Sources/Vitruvian")
        write(self.mono, f"{APP}/Sources/Vitruvian/Core/Foo.swift", FOO_FORK)
        ledger = upstream.Ledger(self.a, self.a_tree, [])
        write(self.mono, upstream.LEDGER, ledger.dump())
        commit(self.mono, "rename and refactor")

        foo = FOO_UPSTREAM
        self.b = self.edit(
            "Sources/Vorssaint/Core/Foo.swift",
            foo := foo.replace("{ 3 }", "{ 30 }"),
            "fix: gamma",
        )
        write(up, ".github/ci.yml", "on: [push, pull_request]\n")
        self.c = commit(up, "ci: run on PRs")
        self.d = self.edit(
            "Sources/Vorssaint/NewArea/Bar.swift",
            HEADER + "struct VorssaintBar {}\n",
            "feat: bar",
        )
        self.e = self.edit(
            "Sources/Vorssaint/Core/Foo.swift",
            foo := foo.replace("{ 1 }", "{ 10 }"),
            "fix: alpha",
        )
        self.f = self.edit(
            "Sources/Vorssaint/Core/Foo.swift",
            foo := foo.replace("{ 2 }", "{ 20 }"),
            "fix: beta",
        )
        self.g = self.edit(
            "Sources/Vorssaint/Core/Foo.swift",
            foo + 'let feed = URL(string: "https://updates.vorssaint.com/feed")!\n',
            "feat: feed",
        )

    def edit(self, rel, text, message):
        write(self.up, rel, text)
        return commit(self.up, message)

    def tool(self, *args):
        argv = [
            "--root",
            str(self.mono),
            "--upstream-url",
            str(self.up),
            "--cache",
            str(self.cache),
            "--import-commit",
            self.import_commit,
            *args,
        ]
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            rc = upstream.main(argv)
        return rc, stdout.getvalue(), stderr.getvalue()

    def ledger(self):
        return upstream.Ledger.load(self.mono / upstream.LEDGER)

    def foo(self):
        return (self.mono / APP / "Sources/Vitruvian/Core/Foo.swift").read_text()


class Base(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        home = Path(self._tmp.name) / "home"
        home.mkdir()
        env = {
            "HOME": str(home),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "t",
            "GIT_AUTHOR_EMAIL": "t@example.com",
            "GIT_COMMITTER_NAME": "t",
            "GIT_COMMITTER_EMAIL": "t@example.com",
        }
        saved = {k: os.environ.get(k) for k in env}
        os.environ.update(env)
        self.addCleanup(
            lambda: [
                os.environ.pop(k) if v is None else os.environ.__setitem__(k, v)
                for k, v in saved.items()
            ]
        )
        self.fx = Fixture(self._tmp.name)


class BrandTest(unittest.TestCase):
    def test_names_become_the_forks(self):
        f = upstream.to_fork_line
        self.assertEqual(
            f('id = "com.vorssaint.utils.dev"\n'),
            'id = "com.vitruviansoftware.vitruvian.dev"\n',
        )
        self.assertEqual(
            f("hideVorssaintWindows VORSSAINT_DEVELOPMENT vorssaint\n"),
            "hideVitruvianWindows VITRUVIAN_DEVELOPMENT vitruvian\n",
        )

    def test_notices_and_upstream_addresses_are_left_alone(self):
        f = upstream.to_fork_line
        for line in (
            "// Copyright (C) 2026 Vorssaint\n",
            "// SPDX-License-Identifier: GPL-3.0-or-later\n",
            'URL(string: "https://screenshots.vorssaint.com/x")\n',
            'let repo = "https://github.com/vorssaint/vorssaint-utils"\n',
            '"/etc/sudoers.d/vorssaint-utils-clamshell"\n',
        ):
            self.assertEqual(f(line), line)
        # ...while the rest of the line is still rebranded.
        self.assertEqual(
            f('Vorssaint.open("https://vorssaint.com")\n'),
            'Vitruvian.open("https://vorssaint.com")\n',
        )

    def test_review_flags_upstream_names_but_not_notices(self):
        text = '// Copyright (C) 2026 Vorssaint\nok\nlet u = "https://vorssaint.com"\n'
        self.assertEqual([n for n, _ in upstream.brand_review(text)], [3])


class LedgerTest(unittest.TestCase):
    def test_errors(self):
        rows = [
            dict(
                sha="a" * 40,
                patch_id="-",
                date="2026-10-01",
                status="ported",
                ref="PR 12",
                subject="x",
                line=1,
            ),
            dict(
                sha="b" * 40,
                patch_id="-",
                date="2026-10-01",
                status="skipped",
                ref="-",
                subject="x",
                line=2,
            ),
            dict(
                sha="b" * 40,
                patch_id="-",
                date="2026-10-01",
                status="pending",
                ref="-",
                subject="x",
                line=3,
            ),
            dict(
                sha="c" * 40,
                patch_id="-",
                date="2026-10-01",
                status="done",
                ref="#1",
                subject="x",
                line=4,
            ),
            dict(
                sha="abc",
                patch_id="-",
                date="2026-10-01",
                status="ported",
                ref="#1,#2",
                subject="x",
                line=5,
            ),
        ]
        errs = "\n".join(upstream.Ledger("a" * 40, "t" * 40, rows).errors())
        self.assertIn("line 1 (aaaaaaaaaa): a ported commit's ref is the PR", errs)
        self.assertIn("line 2 (bbbbbbbbbb): a skipped commit's ref says why", errs)
        self.assertIn("line 3 (bbbbbbbbbb): duplicate of line 2", errs)
        self.assertIn("line 4 (cccccccccc): status 'done'", errs)
        self.assertIn("line 5 (abc): sha is not a full commit id", errs)
        self.assertEqual(errs.count("\n") + 1, 5)

    def test_dump_load_round_trip(self):
        rows = [
            dict(
                sha="a" * 40,
                patch_id="p" * 40,
                date="2026-10-01",
                status="ported",
                ref="#7",
                subject="s",
            )
        ]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "ledger.tsv"
            path.write_text(upstream.Ledger("b" * 40, "t" * 40, rows).dump())
            loaded = upstream.Ledger.load(path)
        self.assertEqual((loaded.base, loaded.tree), ("b" * 40, "t" * 40))
        self.assertEqual({k: loaded.rows[0][k] for k in upstream.COLUMNS}, rows[0])


class PackageTest(unittest.TestCase):
    def restore(self, merged, ours):
        return upstream.restore_package(merged.encode(), ours.encode()).decode()

    def test_new_declaration_follows_its_neighbours(self):
        ours = "package enum Support {\n    package static func a() {}\n    package static func b() {}\n}\n"
        merged = "enum Support {\n    static func a() {}\n    static func c() {}\n    static func b() {}\n}\n"
        self.assertEqual(
            self.restore(merged, ours),
            "package enum Support {\n    package static func a() {}\n"
            "    package static func c() {}\n    package static func b() {}\n}\n",
        )

    def test_private_locals_and_protocol_requirements_are_left_alone(self):
        ours = (
            "package protocol P {\n    func a()\n}\n"
            "package struct S {\n    package func f() {\n        let x = 1\n    }\n"
            "    package func g() {}\n}\n"
        )
        merged = (
            "protocol P {\n    func a()\n    func b()\n}\n"
            "struct S {\n    func f() {\n        let x = 1\n        let y = 2\n    }\n"
            "    private func h() {}\n    func g() {}\n}\n"
        )
        out = self.restore(merged, ours)
        self.assertIn("\n    func b()\n", out)
        self.assertIn("\n        let y = 2\n", out)
        self.assertIn("\n    private func h() {}\n", out)
        self.assertIn("\n    package func g() {}\n", out)

    def test_aligned_parameters_move_with_the_parenthesis(self):
        ours = "package enum E {\n    package static func a() {}\n}\n"
        merged = (
            "enum E {\n    static func a() {}\n"
            "    static func b(_ x: Int,\n                  y: Int) -> Int {\n"
            "        x + y\n    }\n}\n"
        )
        self.assertIn(
            "    package static func b(_ x: Int,\n                          y: Int) -> Int {\n"
            "        x + y\n",
            self.restore(merged, ours),
        )

    def test_a_file_without_package_gets_none(self):
        ours = "final class A {\n    func a() {}\n}\n"
        merged = "final class A {\n    func a() {}\n    func b() {}\n}\n"
        self.assertEqual(self.restore(merged, ours), merged)


class TriageTest(Base):
    def test_status_then_triage(self):
        fx = self.fx
        rc, out, _ = fx.tool("status", "--check")
        self.assertEqual(rc, 1, out)
        self.assertIn("6 untriaged, 0 pending", out)
        rc, _, err = fx.tool("--no-fetch", "triage")
        self.assertEqual(rc, 0, err)
        rows = {r["sha"]: r for r in fx.ledger().rows}
        self.assertEqual(
            [r["sha"] for r in fx.ledger().rows], [fx.b, fx.c, fx.d, fx.e, fx.f, fx.g]
        )
        self.assertEqual(rows[fx.c]["status"], "skipped")
        self.assertEqual(rows[fx.c]["ref"], "touches only upstream-only paths")
        self.assertTrue(
            all(rows[s]["status"] == "pending" for s in (fx.b, fx.d, fx.e, fx.f, fx.g))
        )
        self.assertEqual(fx.tool("--no-fetch", "status", "--check")[0], 0)
        self.assertEqual(fx.tool("check-ledger")[0], 0)

    def test_history_rewrite_is_followed(self):
        fx = self.fx
        fx.tool("triage")
        ledger = fx.ledger()
        ledger.rows[0]["status"], ledger.rows[0]["ref"] = "ported", "#42"
        (fx.mono / upstream.LEDGER).write_text(ledger.dump())
        # Upstream force-pushes the same changes with new commit ids.
        env = dict(os.environ, GIT_COMMITTER_DATE="2030-01-01T00:00:00Z")
        run(fx.up, "rebase", "-q", "--root", "--force-rebase", env=env)
        new_shas = run(fx.up, "log", "--reverse", "--format=%H").split()
        self.assertNotEqual(new_shas[0], fx.a)

        rc, out, _ = fx.tool("status", "--check")
        self.assertEqual(rc, 0, out)
        self.assertIn(f"re-anchored by tree from {fx.a[:10]}", out)
        self.assertIn("6 ledger row(s) re-keyed by patch id", out)
        fx.tool("--no-fetch", "triage")
        ledger = fx.ledger()
        self.assertEqual(ledger.base, new_shas[0])
        self.assertEqual([r["sha"] for r in ledger.rows], new_shas[1:])
        self.assertEqual(
            (ledger.rows[0]["status"], ledger.rows[0]["ref"]), ("ported", "#42")
        )

    def test_markdown_counts_commits_the_issue_did_not_list(self):
        fx = self.fx
        previous = fx.tmp / "body.md"
        previous.write_text(f"<!-- untriaged-shas: {fx.b[:12]} {fx.c[:12]} -->\n")
        rc, out, _ = fx.tool("status", "--markdown", "--previous-body", str(previous))
        self.assertEqual(rc, 0)
        self.assertIn("<!-- upstream-watch untriaged: 6 pending: 0 new: 4 -->", out)
        self.assertIn(f"[`{fx.d[:10]}`]", out)


class PortTest(Base):
    def setUp(self):
        super().setUp()
        self.fx.tool("triage")
        run(self.fx.mono, "add", "-A")
        run(self.fx.mono, "commit", "-q", "-m", "ledger")

    def test_clean_change_lands_on_the_renamed_file(self):
        rc, out, _ = self.fx.tool(
            "--no-fetch", "port", self.fx.b, "--report-dir", str(self.fx.tmp / "r")
        )
        self.assertEqual(rc, 0, out)
        self.assertIn("(renamed): merged", out)
        self.assertEqual(self.fx.foo(), FOO_FORK.replace("{ 3 }", "{ 30 }"))

    def test_package_modifier_does_not_conflict_and_is_kept(self):
        rc, out, _ = self.fx.tool(
            "--no-fetch", "port", self.fx.f, "--report-dir", str(self.fx.tmp / "r")
        )
        self.assertEqual(rc, 0, out)
        self.assertIn("package func beta() -> Int { 20 }\n", self.fx.foo())

    def test_change_to_refactored_code_conflicts(self):
        rc, out, _ = self.fx.tool(
            "--no-fetch", "port", self.fx.e, "--report-dir", str(self.fx.tmp / "r")
        )
        self.assertEqual(rc, 1)
        self.assertIn("1 conflict(s) to resolve", out)
        foo = self.fx.foo()
        self.assertIn("<<<<<<< vitruvian\nfunc alpha() -> Int { 100 }\n", foo)
        self.assertIn("func alpha() -> Int { 10 }\n>>>>>>> upstream", foo)

    def test_new_file_is_placed_and_rebranded_with_upstreams_notice(self):
        rc, out, _ = self.fx.tool(
            "--no-fetch", "port", self.fx.d, "--report-dir", str(self.fx.tmp / "r")
        )
        self.assertEqual(rc, 0, out)
        bar = self.fx.mono / APP / "Sources/Vitruvian/NewArea/Bar.swift"
        self.assertEqual(bar.read_text(), HEADER + "struct VitruvianBar {}\n")

    def test_upstream_address_is_reported_not_rewritten(self):
        rc, out, _ = self.fx.tool(
            "--no-fetch", "port", self.fx.g, "--report-dir", str(self.fx.tmp / "r")
        )
        self.assertEqual(rc, 1)
        self.assertIn("brand review", out)
        self.assertIn('"https://updates.vorssaint.com/feed"', self.fx.foo())

    def test_forks_own_mentions_of_upstream_are_not_flagged(self):
        foo = self.fx.mono / APP / "Sources/Vitruvian/Core/Foo.swift"
        foo.write_text(
            foo.read_text().replace(BODY, '// no link may contain "vorssaint"\n' + BODY)
        )
        run(self.fx.mono, "commit", "-qam", "own mention")
        rc, out, _ = self.fx.tool(
            "--no-fetch", "port", self.fx.b, "--report-dir", str(self.fx.tmp / "r")
        )
        self.assertEqual(rc, 0, out)
        self.assertNotIn("brand review", out)

    def test_dry_run_changes_nothing(self):
        before = self.fx.foo()
        rc, out, _ = self.fx.tool(
            "--no-fetch",
            "port",
            "--dry-run",
            self.fx.e,
            "--report-dir",
            str(self.fx.tmp / "r"),
        )
        self.assertEqual(rc, 1)
        self.assertIn("conflict", out)
        self.assertEqual(self.fx.foo(), before)

    def test_refuses_to_merge_into_uncommitted_work(self):
        foo = self.fx.mono / APP / "Sources/Vitruvian/Core/Foo.swift"
        foo.write_text(foo.read_text() + "// wip\n")
        rc, _, err = self.fx.tool(
            "--no-fetch", "port", self.fx.b, "--report-dir", str(self.fx.tmp / "r")
        )
        self.assertEqual(rc, 2)
        self.assertIn("has uncommitted changes", err)

    def test_upstream_only_paths_are_not_ported(self):
        rc, out, _ = self.fx.tool(
            "--no-fetch", "port", self.fx.c, "--report-dir", str(self.fx.tmp / "r")
        )
        self.assertEqual(rc, 0, out)
        self.assertIn("`.github/ci.yml`: upstream-only path, not ported", out)
        self.assertFalse((self.fx.mono / APP / ".github").exists())


class CommittedLedgerTest(unittest.TestCase):
    """The ledger in this repository is well formed."""

    def test_committed_ledger(self):
        path = Path(
            os.environ.get("UPSTREAM_LEDGER") or Path(__file__).with_name("ledger.tsv")
        )
        ledger = upstream.Ledger.load(path)
        self.assertEqual(ledger.errors(), [])
        self.assertTrue(ledger.rows, "the ledger lists no commits")


if __name__ == "__main__":
    unittest.main()
