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

"""Runs the Go planner (:plan-go) and the Rust planner (:plan) side by side.

Every case builds the same inputs for both -- a scratch git repo, a fake
`bazel` first on PATH whose answers and exit codes the case sets, an
optional dependency map -- runs both binaries with the same arguments, and
requires the same exit code, stdout, stderr, GITHUB_OUTPUT, written files
and bazel calls. Only what is measured, not computed, is masked: the
duration fields and the program name in usage text.

The cases cover plan_test.go, rdepsmap_test.go and units_test.go end to end
(through the CLI), every output format, every flag and the failure paths.
"""

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest

HERE = os.getcwd()
PLAN_GO = os.path.join(HERE, os.environ["PLAN_GO"])
PLAN_RS = os.path.join(HERE, os.environ["PLAN_RS"])
REAL_UNITS = os.path.join(HERE, "tools/pipeline/unitfile/testdata/real_units")

FAKE_BAZEL = """#!/bin/bash
printf '%s\\n' "$*" >> "$FAKE_BAZEL_LOG"
case "$*" in
  *--output=package*) f=packages ;;
  *--output=graph*) f=graph ;;
  *) f=query ;;
esac
d="$FAKE_BAZEL_DIR"
[ -f "$d/$f.err" ] && cat "$d/$f.err" >&2
[ -f "$d/$f.out" ] && cat "$d/$f.out"
exit "$(cat "$d/$f.rc" 2>/dev/null || echo 0)"
"""

GIT_ENV = {
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@example.com",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@example.com",
    "GIT_AUTHOR_DATE": "2026-01-01T00:00:00Z",
    "GIT_COMMITTER_DATE": "2026-01-01T00:00:00Z",
}


def git(repo, *args):
    env = dict(os.environ, **GIT_ENV)
    out = subprocess.run(
        ["git", "-c", "commit.gpgsign=false", *args],
        cwd=repo,
        env=env,
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        raise AssertionError(f"git {args}: {out.stderr}")
    return out.stdout.strip()


def write(root, rel, content):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(content)


def commit(repo, msg, files):
    for rel, content in files.items():
        if content is None:
            os.remove(os.path.join(repo, rel))
        else:
            write(repo, rel, content)
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "--allow-empty", "-m", msg)
    return git(repo, "rev-parse", "HEAD")


UNIT_WEB = """
pipeline_unit(
    name = "fx-web",
    tier = "L1",
    persona = "frontend",
    runner = "ubuntu-26.04",
    test_targets = [":unit_tests", ":a<b>&c"],
    env = {"K": "v"},
)
"""

UNIT_APP = """pipeline_unit(
    name = "fx-app",
    # one (bracketed) comment ) ]
    test_targets = [":test"],
    depends_on = ["fx-web"],
    timeout_minutes = 45,
    runner = "xcode-27",
)
"""

UNIT_MAC = """pipeline_unit(
    name = "fx-mac",
    test_targets = ["//apps/mac:t"],
    runner = "macos-15",
    tier = "L2",
)
"""


class Repo:
    """A scratch repo: c0 (packages), c1 (apps), c2 (code change), c3."""

    def __init__(self, root):
        self.root = root
        os.makedirs(root)
        git(root, "init", "-q", "-b", "main")
        self.c0 = commit(
            root,
            "c0",
            {
                "tabula/web/BUILD": UNIT_WEB,
                "shared/BUILD": "# shared\n",
                "app/BUILD": UNIT_APP,
                "app/sub/BUILD": "",
                "apps/mac/BUILD": UNIT_MAC,
                "docs/index.md": "# docs\n",
                "README.md": "hi\n",
            },
        )
        self.c1 = commit(root, "c1", {"shared/lib.go": "package shared\n"})
        self.c2 = commit(root, "c2", {"tabula/web/src/App.tsx": "x\n"})
        self.c3 = commit(root, "c3", {"app/sub/new_test.go": "package sub\n"})
        git(root, "update-ref", "refs/remotes/origin/main", self.c1)


class PlanParityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="plan-parity-")
        cls.bin = os.path.join(cls.tmp, "bin")
        os.makedirs(cls.bin)
        fb = os.path.join(cls.bin, "bazel")
        with open(fb, "w") as f:
            f.write(FAKE_BAZEL)
        os.chmod(fb, 0o755)
        cls.repo = Repo(os.path.join(cls.tmp, "repo"))
        # Every real pipeline_unit in the repo, laid out at its real path.
        cls.real = os.path.join(cls.tmp, "real")
        os.makedirs(cls.real)
        git(cls.real, "init", "-q", "-b", "main")
        files = {}
        for name in sorted(os.listdir(REAL_UNITS)):
            rel = name[: -len(".txt")].replace("__", "/")
            with open(os.path.join(REAL_UNITS, name)) as f:
                files[rel] = f.read()
        files["README.md"] = "x\n"
        cls.real_c0 = commit(cls.real, "c0", files)
        cls.real_c1 = commit(cls.real, "c1", {"MODULE.bazel": "module(name = 'x')\n"})
        cls.real_c2 = commit(
            cls.real, "c2", {"apps/cli/devx/main.go": "package main\n"}
        )
        cls.n = 0

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    # ---- running ------------------------------------------------------------

    def fake(self, d, name, out="", err="", rc=0):
        with open(os.path.join(d, name + ".out"), "w") as f:
            f.write(out)
        with open(os.path.join(d, name + ".err"), "w") as f:
            f.write(err)
        with open(os.path.join(d, name + ".rc"), "w") as f:
            f.write(str(rc))

    def run_one(self, binary, args, case_dir, env_extra, cwd, gh_output, files):
        side = os.path.join(case_dir, "go" if binary == PLAN_GO else "rs")
        os.makedirs(side, exist_ok=True)
        log = os.path.join(side, "bazel.log")
        env = {
            "PATH": self.bin + ":/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": self.tmp,
            "FAKE_BAZEL_DIR": os.path.join(case_dir, "fake"),
            "FAKE_BAZEL_LOG": log,
            "TMPDIR": self.tmp,
        }
        env.update(GIT_ENV)
        if gh_output:
            env["GITHUB_OUTPUT"] = os.path.join(side, "github_output")
            if gh_output == "prefilled":
                with open(env["GITHUB_OUTPUT"], "w") as f:
                    f.write("existing=1\n")
        for k, v in env_extra.items():
            if v is None:
                env.pop(k, None)
            else:
                env[k] = v.replace("{SIDE}", side)
        real_args = [a.replace("{SIDE}", side) for a in args]
        p = subprocess.run(
            [binary, *real_args], cwd=cwd or self.tmp, env=env, capture_output=True
        )
        result = {
            "rc": p.returncode,
            "stdout": self.norm(p.stdout.decode(errors="replace"), binary, side),
            "stderr": self.norm(p.stderr.decode(errors="replace"), binary, side),
        }
        if os.path.exists(log):
            with open(log) as f:
                result["bazel_calls"] = f.read()
        if gh_output and os.path.exists(env["GITHUB_OUTPUT"]):
            with open(env["GITHUB_OUTPUT"]) as f:
                result["github_output"] = f.read()
        for rel in files:
            p2 = os.path.join(side, rel)
            if os.path.exists(p2):
                with open(p2) as f:
                    result["file:" + rel] = self.norm(f.read(), binary, side)
            else:
                result["file:" + rel] = None
        return result

    def norm(self, text, binary, side):
        text = text.replace(binary, "PROG").replace(side, "SIDE")
        text = re.sub(r'"duration_ms": \d+', '"duration_ms": 0', text)
        text = re.sub(r'"duration_ms":\d+', '"duration_ms":0', text)
        text = re.sub(r"Duration:( +)\d+ ms", r"Duration:\1N ms", text)
        text = re.sub(r"bytes, \d+(h\d+m)?(m)?\d*s\n", "bytes, Ns\n", text)
        return text

    def check(
        self,
        args,
        *,
        query=None,
        packages=None,
        graph=None,
        env=None,
        cwd=None,
        gh_output=False,
        files=(),
        setup=None,
        expect_rc=None,
        expect_in=None,
    ):
        """Runs both planners on one case and requires the same result."""
        type(self).n += 1
        case_dir = os.path.join(self.tmp, f"case{self.n}")
        fake_dir = os.path.join(case_dir, "fake")
        os.makedirs(fake_dir)
        for name, spec in (("query", query), ("packages", packages), ("graph", graph)):
            if spec is not None:
                self.fake(fake_dir, name, *spec)
        if setup:
            setup(case_dir)
        go = self.run_one(PLAN_GO, args, case_dir, env or {}, cwd, gh_output, files)
        rs = self.run_one(PLAN_RS, args, case_dir, env or {}, cwd, gh_output, files)
        self.assertEqual(go, rs, f"args {args}")
        if expect_rc is not None:
            self.assertEqual(go["rc"], expect_rc, go)
        if expect_in is not None:
            blob = json.dumps(go)
            self.assertIn(expect_in, blob, go)
        return go

    def r(self, *extra):
        return ["--repo-root=" + self.repo.root, *extra]

    # ---- the plan itself ---------------------------------------------------------

    def test_formats_over_a_live_query(self):
        q = (
            "//tabula/web:unit_tests\n//tabula/web:a<b>&c\nnot-a-label\n",
            "Loading...\n",
            0,
        )
        base = ["--base=" + self.repo.c1, "--head=" + self.repo.c2]
        for fmt in ["json", "text", "targets", "matrix", "bogus"]:
            self.check(self.r(*base, "--format=" + fmt), query=q, expect_rc=0)
        self.check(
            self.r(*base, "--format=github-matrix"),
            query=q,
            gh_output=True,
            expect_rc=0,
        )
        self.check(
            self.r(*base, "--output-github-matrix"),
            query=q,
            gh_output="prefilled",
            expect_rc=0,
        )
        self.check(
            self.r(*base, "-output-github-matrix=false", "-format", "text"), query=q
        )
        self.check(self.r(*base, "--format=github-matrix"), query=q, expect_rc=0)
        self.check(
            self.r(*base, "--output-file={SIDE}/out.json"),
            query=q,
            files=["out.json"],
            expect_rc=0,
        )
        self.check(
            self.r(*base, "--output-file={SIDE}/no/such/dir/out.json"),
            query=q,
            expect_rc=1,
        )

    def test_each_kind_of_change(self):
        q = ("//tabula/web:unit_tests\n", "", 0)
        repo = self.repo
        cases = [
            [repo.c0, repo.c1],  # shared/ only: no unit via the query
            [repo.c1, repo.c2],  # tabula/web
            [repo.c2, repo.c3],  # app/sub: inside app
            [repo.c0, repo.c3],
            [repo.c3, repo.c3],  # nothing changed
        ]
        for base, head in cases:
            for fmt in ["json", "text"]:
                self.check(
                    self.r("--base=" + base, "--head=" + head, "--format=" + fmt),
                    query=q,
                )

    def test_docs_global_and_no_package_changes(self):
        repo = self.repo
        d = os.path.join(self.tmp, "kinds")
        shutil.copytree(repo.root, d, symlinks=True)
        c_docs = commit(d, "docs", {"docs/more.md": "x\n", "OWNERS": "x\n"})
        c_glob = commit(d, "glob", {"MODULE.bazel": "x\n"})
        c_tool = commit(d, "tool", {"tools/remote.bazelrc": "x\n"})
        c_inert = commit(d, "inert", {"tools/ci/x.sh": "x\n"})
        c_root = commit(
            d, "root", {"main.go": "package main\n", "migrations/x.sql": "x\n"}
        )
        c_lock = commit(d, "lock", {"pnpm-lock.yaml": "x\n"})
        prev = repo.c3
        for c in [c_docs, c_glob, c_tool, c_inert, c_root, c_lock]:
            for fmt in ["json", "github-matrix", "text"]:
                self.check(
                    [
                        "--repo-root=" + d,
                        "--base=" + prev,
                        "--head=" + c,
                        "--format=" + fmt,
                    ],
                    query=("", "", 0),
                    gh_output=fmt == "github-matrix",
                )
            prev = c

    def test_every_real_unit(self):
        # A global change selects every unit: the whole matrix of real units.
        for fmt in ["json", "matrix", "github-matrix"]:
            self.check(
                [
                    "--repo-root=" + self.real,
                    "--base=" + self.real_c0,
                    "--head=" + self.real_c1,
                    "--format=" + fmt,
                ],
                expect_rc=0,
            )
        # A scoped change, with the live query naming some real targets.
        self.check(
            [
                "--repo-root=" + self.real,
                "--base=" + self.real_c1,
                "--head=" + self.real_c2,
            ],
            query=("//apps/cli/devx:devx_test\n//apps/mcp/slack:x_test\n", "", 0),
            expect_rc=0,
        )

    def test_degraded_queries(self):
        base = ["--base=" + self.repo.c1, "--head=" + self.repo.c2]
        noisy = (
            "".join(f"Loading: {i} packages\n" for i in range(40))
            + "ERROR: the real reason\n"
        )
        for fmt in ["json", "github-matrix", "text"]:
            self.check(
                self.r(*base, "--format=" + fmt), query=("", noisy, 1), expect_rc=0
            )
        external = (
            "ERROR: /x/external/rules_android+/BUILD:1:1: no such target '@@r//:x'\n"
            "ERROR: no such package '@@some_repo//': fetch failed\n"
            'ERROR: Evaluation of query "x" failed: errors were encountered\n'
        )
        self.check(self.r(*base), query=("//tabula/web:unit_tests\n", external, 3))
        internal = (
            external
            + "ERROR: "
            + self.repo.root
            + "/apps/x/BUILD:3:1: bad\nERROR: Skipping '//apps/x': no\n"
        )
        self.check(
            self.r(*base, "--format=github-matrix"),
            query=("//tabula/web:unit_tests\n", internal, 3),
        )
        self.check(self.r(*base), query=("", "killed\n", 137))
        # No bazel at all.
        self.check(
            self.r(*base),
            env={"PATH": "/usr/bin:/bin"},
            expect_in="executable file not found",
        )

    def test_diff_bases(self):
        repo = self.repo
        q = ("//tabula/web:unit_tests\n", "", 0)
        for extra in [
            ["--base-ref=main"],
            ["--base-ref=nosuch"],
            ["--base-sha=" + repo.c0],
            ["--before-rev=" + repo.c1],
            ["--base=" + repo.c2, "--base-sha=" + repo.c0],
            [],
            ["--head=" + repo.c2],
            ["--base=nosuchrev"],
            ["--base=" + repo.c0, "--head=nosuchrev"],
            ["--event=push", "--base=" + repo.c0],
        ]:
            self.check(self.r(*extra), query=q)

        # No origin/main: HEAD~1; and a one-commit repo where that fails too.
        d = os.path.join(self.tmp, "noorigin")
        shutil.copytree(repo.root, d, symlinks=True)
        git(d, "update-ref", "-d", "refs/remotes/origin/main")
        self.check(["--repo-root=" + d], query=q)
        one = os.path.join(self.tmp, "onecommit")
        os.makedirs(one)
        git(one, "init", "-q")
        commit(one, "only", {"a/BUILD": UNIT_WEB})
        self.check(["--repo-root=" + one], query=q)
        # The working tree: an uncommitted edit and an untracked file.
        wt = os.path.join(self.tmp, "worktree")
        shutil.copytree(repo.root, wt, symlinks=True)
        write(wt, "shared/lib.go", "package shared // edited\n")
        write(wt, "tabula/web/new.ts", "x\n")
        self.check(["--repo-root=" + wt, "--base=" + repo.c2], query=q)
        # Not a git repo at all; a repo root that does not exist.
        self.check(["--repo-root=" + self.tmp + "/nowhere"], query=q)
        plain = os.path.join(self.tmp, "plain")
        os.makedirs(plain, exist_ok=True)
        self.check(["--repo-root=" + plain], query=q)

    def test_repo_root_sources(self):
        q = ("//tabula/web:unit_tests\n", "", 0)
        base = ["--base=" + self.repo.c1, "--head=" + self.repo.c2]
        self.check(base, query=q, env={"BUILD_WORKSPACE_DIRECTORY": self.repo.root})
        self.check(base, query=q, cwd=self.repo.root)
        self.check(base, query=q, cwd=self.repo.root + "/tabula")

    def test_timeouts(self):
        q = ("//tabula/web:unit_tests\n", "", 0)
        for t in ["0", "-5", "9223372036854775807"]:
            self.check(
                self.r(
                    "--base=" + self.repo.c1,
                    "--head=" + self.repo.c2,
                    "--timeout-sec=" + t,
                ),
                query=q,
            )

    def test_unreadable_and_duplicate_units(self):
        d = os.path.join(self.tmp, "broken")
        shutil.copytree(self.repo.root, d, symlinks=True)
        write(
            d,
            "apps/broken/BUILD",
            '\npipeline_unit(\n    name = "broken-unit",\n    test_targets = glob(["*_test.go"]),\n)\n',
        )
        write(
            d,
            "apps/dup/BUILD",
            'pipeline_unit(name = "fx-web", test_targets = [":t"])\n',
        )
        write(
            d,
            "apps/open/BUILD",
            'pipeline_unit(\n    name = "never",\n    runner = "x,\n',
        )
        write(
            d,
            "apps/eof/BUILD",
            'pipeline_unit(\n    name = "eof",\n    env = {"A": """oops},\n)\n',
        )
        write(
            d,
            "apps/unclosed/BUILD",
            '\npipeline_unit(\n    name = "unclosed",\n    test_targets = [":a"],\n',
        )
        write(
            d,
            "apps/wrong/BUILD",
            'pipeline_unit(\n    name = "wrong",\n    test_targets = [":a"),\n)\n',
        )
        write(
            d,
            "apps/prefix/BUILD",
            "x = r'unclosed\npipeline_unit(name = 'p', test_targets = [':a'])\n",
        )
        write(d, "apps/positional/BUILD", 'pipeline_unit("u", [":a"])\n')
        write(
            d,
            "apps/types/BUILD",
            'pipeline_unit(name = "t", timeout_minutes = 2 * 30, test_targets = [":a"])\n',
        )
        write(d, "apps/noname/BUILD", 'pipeline_unit(test_targets = [":a"])\n')
        b = commit(d, "broken", {})
        self.check(
            ["--repo-root=" + d, "--base=" + self.repo.c1, "--head=" + b], expect_rc=1
        )
        # Docs-only never reads the units, so it still plans; an empty diff
        # is not docs-only, so it does read them and fails.
        docs = commit(d, "docs", {"docs/more.md": "x\n"})
        self.check(["--repo-root=" + d, "--base=" + b, "--head=" + docs], expect_rc=0)
        self.check(
            ["--repo-root=" + d, "--base=" + docs, "--head=" + docs], expect_rc=1
        )

    # ---- the dependency map ----------------------------------------------------

    def write_map(self, case_dir, content):
        for side in ("go", "rs"):
            p = os.path.join(case_dir, side)
            os.makedirs(p, exist_ok=True)
            with open(os.path.join(p, "map.json"), "w") as f:
                f.write(content)

    def map_case(self, content, args, **kw):
        def setup(case_dir):
            if content is not None:
                self.write_map(case_dir, content)

        return self.check(
            self.r("--rdeps-map={SIDE}/map.json", *args), setup=setup, **kw
        )

    def test_rdeps_map(self):
        repo = self.repo
        good = {
            "schema": 1,
            "commit": repo.c1,
            "packages": ["shared", "tabula/web", "app", "app/sub", "apps/mac"],
            "tests": {
                "shared": ["//app:test"],
                "tabula/web": ["//tabula/web:unit_tests"],
            },
        }
        base = ["--base=" + repo.c1, "--head=" + repo.c3]
        q = ("//tabula/web:unit_tests\n", "", 0)
        self.map_case(json.dumps(good), base, query=q, expect_in="rdeps-map")
        self.map_case(json.dumps(good), base + ["--format=github-matrix"], query=q)
        self.map_case(None, base, query=q, expect_in="no dependency map")
        self.map_case(json.dumps(dict(good, commit=repo.c0)), base, query=q)
        self.map_case(json.dumps(dict(good, schema=2)), base, query=q)
        self.map_case(json.dumps(dict(good, packages=[])), base, query=q)
        self.map_case(json.dumps(dict(good, packages=None)), base, query=q)
        self.map_case(json.dumps(dict(good, Schema="1")), base, query=q)
        self.map_case(
            json.dumps(
                {"SCHEMA": 1, "Commit": repo.c1, "PACKAGES": ["app"], "tests": {}}
            ),
            base,
            query=q,
        )
        self.map_case(json.dumps(dict(good, packages=["a", 1])), base, query=q)
        self.map_case(json.dumps(dict(good, tests={"a": "x"})), base, query=q)
        self.map_case(json.dumps(dict(good, tests=["a"])), base, query=q)
        self.map_case(json.dumps(dict(good, schema=1.5)), base, query=q)
        self.map_case(json.dumps(dict(good, commit=None)), base, query=q)
        for bad in [
            "not json",
            "",
            "{",
            '{"schema":1,}',
            "[]",
            "null",
            '"x"',
            '{"a":1} x',
            '{"a" 1}',
            '{"a":tru}',
            '{"a":"\\q"}',
            "[1,]",
            "01",
        ]:
            self.map_case(bad, base, query=q)
        # A package the map does not know falls back to the live query.
        unknown = dict(good, packages=["shared"])
        self.map_case(
            json.dumps(unknown),
            base,
            query=q,
            expect_in="does not know every changed package",
        )
        # The map file is a directory.
        self.check(self.r("--rdeps-map=" + self.tmp, *base), query=q)

    def test_earlier_map(self):
        repo = self.repo
        q = ("//tabula/web:unit_tests\n", "", 0)
        d = os.path.join(self.tmp, "earlier")
        shutil.copytree(repo.root, d, symlinks=True)
        g = commit(d, "global", {"MODULE.bazel": "x\n"})
        a = commit(d, "after-global", {"shared/x.go": "package shared\n"})
        b = commit(d, "head", {"tabula/web/y.ts": "y\n"})

        def m(commit_):
            return json.dumps(
                {
                    "schema": 1,
                    "commit": commit_,
                    "packages": ["shared", "tabula/web", "app", "app/sub", "apps/mac"],
                    "tests": {"shared": ["//app:test"]},
                }
            )

        def run(map_commit, base, head, behind, fmt="json"):
            def setup(case_dir):
                self.write_map(case_dir, m(map_commit))

            return self.check(
                [
                    "--repo-root=" + d,
                    "--base=" + base,
                    "--head=" + head,
                    "--rdeps-map={SIDE}/map.json",
                    "--rdeps-map-max-behind=" + str(behind),
                    "--format=" + fmt,
                ],
                setup=setup,
                query=q,
            )

        run(repo.c2, repo.c3, b, 9)  # one behind: widened
        run(repo.c1, repo.c3, b, 9)  # two behind
        run(repo.c1, repo.c3, b, 1)  # past the limit
        run(repo.c3, a, b, 9)  # a global change in between
        run(b, repo.c3, b, 9)  # map newer than the base
        run("0" * 40, repo.c3, b, 9)  # unrelated commit
        run("zzz", repo.c3, b, 9)
        run(repo.c3, repo.c3, b, 9)  # exact map
        run(repo.c2, repo.c3, b, 0)  # max-behind 0: off
        run(repo.c2, repo.c3, b, -1)
        run(repo.c2, repo.c3, b, 9, "github-matrix")
        run(repo.c2, repo.c0, repo.c0, 9)  # docs-only: never consults it
        run(repo.c2, g, a, 9)

    def test_emit_rdeps_map(self):
        dot = (
            "digraph mygraph {\n  node [shape=box];\n"
            '  "//app:test"\n  "//app:test" -> "//app:lib"\n'
            '  "//app:lib" -> "@rules_x//:wrapper"\n'
            '  "@rules_x//:wrapper" -> "@@//shared:lib"\n'
            '  "//other:test"\r\n  "//other:test" -> "//other:lib"\n'
            '  "//shared:lib"\n  "//other:lib"\n}\n'
        )
        good = {
            "query": ("//app:test\n//other:test\n\n", "", 0),
            "packages": ("app\nother\nshared\nunused\n", "", 0),
            "graph": (dot, "", 0),
        }
        self.check(
            self.r("--emit-rdeps-map={SIDE}/out.json"),
            files=["out.json"],
            expect_rc=0,
            **good,
        )
        self.check(
            self.r("--emit-rdeps-map={SIDE}/out.json"),
            files=["out.json"],
            expect_rc=0,
            query=("", "", 0),
            packages=("", "", 0),
            graph=("digraph {}\n", "", 0),
        )
        self.check(
            self.r("--emit-rdeps-map={SIDE}/out.json"),
            files=["out.json"],
            expect_rc=1,
            query=("", "".join(f"l{i}\n" for i in range(30)), 2),
        )
        self.check(
            self.r("--emit-rdeps-map={SIDE}/out.json"),
            files=["out.json"],
            expect_rc=1,
            query=good["query"],
            packages=good["packages"],
            graph=('"//a:x\\n//a:y" -> "//b:z"\n', "", 0),
        )
        self.check(
            self.r("--emit-rdeps-map={SIDE}/no/dir/out.json"), expect_rc=1, **good
        )
        self.check(
            [
                "--repo-root=" + self.tmp + "/nowhere",
                "--emit-rdeps-map={SIDE}/out.json",
            ],
            expect_rc=1,
        )
        self.check(
            self.r("--emit-rdeps-map={SIDE}/out.json"),
            env={"PATH": "/usr/bin:/bin"},
            expect_rc=1,
        )

    # ---- flags ----------------------------------------------------------------

    def test_flags(self):
        q = ("//tabula/web:unit_tests\n", "", 0)
        base = ["--base=" + self.repo.c1, "--head=" + self.repo.c2]
        for args in [
            ["-h"],
            ["-help"],
            ["--help"],
            ["-nope"],
            ["--timeout-sec=abc"],
            ["--timeout-sec=99999999999999999999"],
            ["--timeout-sec"],
            ["--format"],
            ["-output-github-matrix=maybe"],
            ["---x"],
            ["-=x"],
            ["--rdeps-map-max-behind=0x10"],
            ["--rdeps-map-max-behind=1_0"],
            ["--rdeps-map-max-behind=08"],
        ]:
            self.check(self.r(*base, *args), query=q)
        # Parsing stops at the first argument that is not a flag, and at --.
        self.check(self.r(*base, "positional", "--format=text"), query=q)
        self.check(self.r(*base, "--", "--format=text"), query=q)
        self.check(self.r(*base, "-", "--format=text"), query=q)
        # Repeats: the last wins; one and two dashes are the same.
        self.check(self.r(*base, "-format=text", "--format", "targets"), query=q)
        self.check(["-repo-root", self.repo.root, *base, "-format=matrix"], query=q)


if __name__ == "__main__":
    unittest.main()
