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

"""conflict-precheck, the Rust port, against the Go original: same exit code,
stdout and stderr, byte for byte, on every input here.

    bazel test //tools/copybara/conflict-precheck:conflict_precheck_rs_parity_test

Each case builds real git repos in a temp dir, then runs both binaries on
them with the same arguments and environment. The cases:
  * every scenario in main_test.go;
  * usage errors (too few arguments, unknown and empty directions);
  * labels the regexp must and must not match (short, long, not at a line
    start, upper-case hex, several per message, the newest commit wins);
  * pending commits: several, merges (excluded), subjects with leading and
    trailing Unicode spaces, standalone_only and BUILD-file exclusions;
  * components with capitals, non-ASCII and invalid UTF-8 (the label is
    Go's strings.ToUpper of it), and pathspec-looking ones;
  * repos that are missing, empty or not repos, and git missing from PATH or
    found only through a relative PATH entry (os/exec refuses that).
"""

import os
import shutil
import subprocess
import tempfile
import unittest

GO = os.environ.get("CONFLICT_PRECHECK_GO", "")
RS = os.environ.get("CONFLICT_PRECHECK_RS", "")
GIT = shutil.which("git") or ""


def _bin(path):
    if not path:
        raise unittest.SkipTest("run this under bazel test")
    return os.path.abspath(path)


class Repo:
    def __init__(self, root, name, init=True):
        self.path = os.path.join(root, name)
        os.makedirs(self.path)
        self.n = 0
        if init:
            self.git("init", "-q", "-b", "main")
            self.git("config", "user.email", "test@example.com")
            self.git("config", "user.name", "Test")
            self.git("config", "commit.gpgsign", "false")
            self.commit("README.md", "init\n", "init")

    def git(self, *args):
        out = subprocess.run(
            [GIT, *args],
            cwd=self.path,
            env=git_env(),
            capture_output=True,
            check=True,
        )
        return out.stdout.decode().strip()

    def commit(self, name, content, msg):
        p = os.path.join(self.path, name)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(content)
        self.n += 1
        self.git("add", "--", name)
        self.git("commit", "-q", "-m", msg)
        return self.git("rev-parse", "HEAD")

    def bpath(self):
        return os.fsencode(self.path)


def git_env():
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": os.environ.get("TEST_TMPDIR", tempfile.gettempdir()),
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_AUTHOR_DATE": "2026-01-01T00:00:00Z",
        "GIT_COMMITTER_DATE": "2026-01-01T00:00:00Z",
        "LC_ALL": "C",
    }
    return env


class Parity(unittest.TestCase):
    def setUp(self):
        self.go = _bin(GO)
        self.rs = _bin(RS)
        if not GIT:
            self.skipTest("git is not on PATH")
        self.tmp = tempfile.mkdtemp(dir=os.environ.get("TEST_TMPDIR"))
        self.cases = 0

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def repos(self):
        root = tempfile.mkdtemp(dir=self.tmp)
        return Repo(root, "mono"), Repo(root, "std")

    def run_both(self, args, env=None, cwd=None):
        env = env if env is not None else git_env()
        res = []
        for b in (self.go, self.rs):
            p = subprocess.run(
                [b, *args], env=env, cwd=cwd or self.tmp, capture_output=True
            )
            res.append((p.returncode, p.stdout, p.stderr))
        return res

    def same(self, args, env=None, cwd=None, want_code=None):
        go, rs = self.run_both(args, env=env, cwd=cwd)
        self.cases += 1
        self.assertEqual(go, rs, "args=%r" % (args,))
        if want_code is not None:
            self.assertEqual(go[0], want_code, "args=%r: %r" % (args, go))
        return go

    # --- main_test.go -------------------------------------------------------

    def test_main_test_scenarios(self):
        m, s = self.repos()
        self.same([b"export", b"devx", m.bpath(), s.bpath()], want_code=0)
        self.same([b"import", b"devx", m.bpath(), s.bpath()], want_code=0)

        m, s = self.repos()
        m.commit("x.txt", "v", "import sync\n\nDEVX_REV_ID: deadbeef123\n")
        self.same([b"export", b"devx", m.bpath(), s.bpath()], want_code=0)

        m, s = self.repos()
        s.commit("x.txt", "v", "export sync\n\nMONOREPO_REV_ID: deadbeef456\n")
        self.same([b"import", b"devx", m.bpath(), s.bpath()], want_code=0)

        m, s = self.repos()
        base = s.commit(
            "src.go", "v1", "feat: initial import\n\nMONOREPO_REV_ID: abc0001\n"
        )
        m.commit("z.txt", "v", "import sync\n\nDEVX_REV_ID: %s\n" % base)
        s.commit("standalone.go", "new", "feat: standalone genuine change")
        out = self.same([b"export", b"devx", m.bpath(), s.bpath()], want_code=1)
        self.assertIn(b"Offending un-synced commit(s):", out[1])

        m, s = self.repos()
        base = s.commit("src.go", "v1", "feat: init\n\nMONOREPO_REV_ID: abc0002\n")
        m.commit("z.txt", "v", "import sync\n\nDEVX_REV_ID: %s\n" % base)
        s.commit(
            "synced.go", "synced", "sync: from monorepo\n\nMONOREPO_REV_ID: feedbeef\n"
        )
        self.same([b"export", b"devx", m.bpath(), s.bpath()], want_code=0)

        m, s = self.repos()
        base = m.commit("devx/src.go", "v1", "feat: init")
        s.commit("z.txt", "v", "export sync\n\nMONOREPO_REV_ID: %s\n" % base)
        m.commit("devx/new.go", "new", "feat: genuine monorepo change")
        self.same([b"import", b"devx", m.bpath(), s.bpath()], want_code=1)

        m, s = self.repos()
        base = m.commit("devx/src.go", "v1", "feat: init\n\nDEVX_REV_ID: 0000001\n")
        s.commit("z.txt", "v", "export sync\n\nMONOREPO_REV_ID: %s\n" % base)
        self.same([b"import", b"devx", m.bpath(), s.bpath()], want_code=0)

        self.same([b"sideways", b"devx", b"/tmp", b"/tmp"], want_code=2)

        m, s = self.repos()
        base = s.commit("src.go", "v1", "feat: init\n\nMONOREPO_REV_ID: abc0003\n")
        m.commit("z.txt", "v", "import sync\n\nDEVX_REV_ID: %s\n" % base)
        s.commit(".github/workflows/sync.yaml", "wf", "ci: update dispatch workflow")
        self.same(
            [b"export", b"devx", m.bpath(), s.bpath(), b".github/workflows/sync.yaml"],
            want_code=0,
        )

    # --- usage --------------------------------------------------------------

    def test_usage(self):
        for args in (
            [],
            [b"export"],
            [b"export", b"devx"],
            [b"import", b"devx", b"/x"],
        ):
            self.same(args, want_code=2)
        for d in (b"", b"EXPORT", b"export ", b"\xff", "exéport".encode()):
            self.same([d, b"devx", b"/nonexistent", b"/nonexistent"], want_code=2)

    # --- labels -------------------------------------------------------------

    def test_label_matching(self):
        msgs = [
            "x\n\nMONOREPO_REV_ID: abc123\n",  # 6 chars: no match
            "x\n\nMONOREPO_REV_ID: ABC1234\n",  # upper-case hex: no match
            "x\n\n  MONOREPO_REV_ID: abc1234\n",  # not at a line start
            "x\n\nMONOREPO_REV_ID:abc1234\n",  # no space
            "x\n\nMONOREPO_REV_ID: " + "a" * 45 + "\n",  # first 40 only
            "x\n\nMONOREPO_REV_ID: 1234567zzz\n",  # trailing junk is fine
            "x\n\nMONOREPO_REV_ID: zzz\nMONOREPO_REV_ID: 7654321\n",
            "MONOREPO_REV_ID: 1111111 is the subject\n",
            "x\n\nMONOREPO_REV_ID: abc1234\r\nMONOREPO_REV_ID: 2222222\n",
        ]
        for msg in msgs:
            m, s = self.repos()
            s.commit("a.txt", "v", msg)
            self.same([b"import", b"devx", m.bpath(), s.bpath()])
        # The newest commit with the label wins, even if a later one lacks it.
        m, s = self.repos()
        s.commit("a.txt", "1", "one\n\nMONOREPO_REV_ID: 1111111\n")
        s.commit("b.txt", "2", "two\n\nMONOREPO_REV_ID: 2222222\n")
        s.commit("c.txt", "3", "three, no label")
        self.same([b"import", b"devx", m.bpath(), s.bpath()])

    # --- pending commits ----------------------------------------------------

    def test_pending_shapes(self):
        m, s = self.repos()
        base = s.commit("src.go", "v1", "feat: init\n\nMONOREPO_REV_ID: abc0001\n")
        m.commit("z.txt", "v", "import sync\n\nDEVX_REV_ID: %s\n" % base)
        s.commit("a.go", "a", "feat: first")
        s.commit("b.go", "b", " feat: second with nbsp　")
        s.commit("c.go", "c", "sync: synced\n\nMONOREPO_REV_ID: 9999999\n")
        s.commit("d.go", "d", "fix: café  ")
        self.same([b"export", b"devx", m.bpath(), s.bpath()], want_code=1)
        self.same(
            [b"export", b"devx", m.bpath(), s.bpath(), b"a.go", b"b.go", b"d.go"],
            want_code=0,
        )
        self.same([b"export", b"devx", m.bpath(), s.bpath(), b"a.go"], want_code=1)

        # A merge commit is excluded; the commit it brings in is not.
        m, s = self.repos()
        base = s.commit("src.go", "v1", "feat: init\n\nMONOREPO_REV_ID: abc0001\n")
        m.commit("z.txt", "v", "import sync\n\nDEVX_REV_ID: %s\n" % base)
        s.git("checkout", "-q", "-b", "side")
        s.commit("side.go", "s", "sync: side\n\nMONOREPO_REV_ID: 8888888\n")
        s.git("checkout", "-q", "main")
        s.commit("main.go", "m", "sync: main\n\nMONOREPO_REV_ID: 7777777\n")
        s.git("merge", "-q", "--no-ff", "-m", "Merge branch side", "side")
        self.same([b"export", b"devx", m.bpath(), s.bpath()], want_code=0)

        # Import side: BUILD files under the component are monorepo-only.
        m, s = self.repos()
        base = m.commit("devx/src.go", "v1", "feat: init")
        s.commit("z.txt", "v", "export sync\n\nMONOREPO_REV_ID: %s\n" % base)
        m.commit("devx/pkg/BUILD.bazel", "x", "build: gazelle")
        m.commit("devx/BUILD", "x", "build: root")
        m.commit("other/file.go", "x", "feat: outside the component")
        m.commit("devx/x.go", "x", "sync: imported\n\nDEVX_REV_ID: 1234567\n")
        self.same([b"import", b"devx", m.bpath(), s.bpath()], want_code=0)
        m.commit("devx/pkg/BUILD.txt", "x", "feat: not a BUILD file")
        self.same([b"import", b"devx", m.bpath(), s.bpath()], want_code=1)

    def test_components(self):
        for comp in (
            b"mcp-slack",
            b"Nexus-Agent",
            "straße-ǆ".encode(),
            b"bad\xffname",
            b"devx/",
            b"",
            b"-",
            b":(glob)*",
        ):
            m, s = self.repos()
            name = comp.decode("utf-8", "replace").strip("/")
            base = m.commit(name + "/src.go" if name else "root.go", "v1", "feat: init")
            s.commit("z.txt", "v", "export sync\n\nMONOREPO_REV_ID: %s\n" % base)
            m.commit("later.go", "x", "feat: later")
            self.same([b"import", comp, m.bpath(), s.bpath()])
            self.same([b"export", comp, m.bpath(), s.bpath()])

    def test_upper_case_label_from_component(self):
        # The import label is strings.ToUpper(component): Go's simple case
        # mapping (ß stays ß) and U+FFFD for invalid bytes.
        for comp, label in (
            ("straße".encode(), "STRAßE_REV_ID".encode()),
            (b"a\xffb", "A�B_REV_ID".encode()),
            ("ǆx".encode(), "ǄX_REV_ID".encode()),
        ):
            m, s = self.repos()
            base = s.commit("src.go", "v1", "init\n\nMONOREPO_REV_ID: abc0001\n")
            m.commit(
                "z.txt",
                "v",
                (b"import\n\n" + label + b": " + base.encode() + b"\n").decode("utf-8"),
            )
            s.commit("new.go", "n", "feat: genuine")
            self.same([b"export", comp, m.bpath(), s.bpath()], want_code=1)

    # --- environment --------------------------------------------------------

    def test_repos_that_are_not_there(self):
        root = tempfile.mkdtemp(dir=self.tmp)
        empty = Repo(root, "empty", init=False)
        subprocess.run([GIT, "init", "-q", empty.path], env=git_env(), check=True)
        plain = Repo(root, "plain", init=False)
        m, s = self.repos()
        s.commit(
            "z.txt", "v", "x\n\nMONOREPO_REV_ID: %s\n" % m.git("rev-parse", "HEAD")
        )
        for a, b in (
            (b"/nonexistent/mono", b"/nonexistent/std"),
            (empty.bpath(), empty.bpath()),
            (plain.bpath(), plain.bpath()),
            (m.bpath(), b"/nonexistent"),
            (b"/nonexistent", s.bpath()),
        ):
            for d in (b"export", b"import"):
                self.same([d, b"devx", a, b])
        # Baseline reachable, but the monorepo moved on with no HEAD history.
        self.same([b"import", b"devx", m.bpath(), s.bpath()])

    def test_git_not_on_path(self):
        m, s = self.repos()
        s.commit(
            "z.txt", "v", "x\n\nMONOREPO_REV_ID: %s\n" % m.git("rev-parse", "HEAD")
        )
        env = git_env()
        env["PATH"] = "/nonexistent"
        self.same([b"import", b"devx", m.bpath(), s.bpath()], env=env, want_code=0)
        del env["PATH"]
        self.same([b"import", b"devx", m.bpath(), s.bpath()], env=env, want_code=0)
        # git only through a relative PATH entry: os/exec refuses (ErrDot).
        bindir = os.path.join(self.tmp, "relbin")
        os.makedirs(bindir, exist_ok=True)
        link = os.path.join(bindir, "git")
        if not os.path.exists(link):
            os.symlink(GIT, link)
        env["PATH"] = "relbin"
        self.same(
            [b"import", b"devx", m.bpath(), s.bpath()],
            env=env,
            cwd=self.tmp,
            want_code=0,
        )
        env["PATH"] = bindir
        self.same([b"import", b"devx", m.bpath(), s.bpath()], env=env, want_code=0)
        # A directory named git earlier on PATH is skipped.
        dirgit = os.path.join(self.tmp, "dirgit")
        os.makedirs(os.path.join(dirgit, "git"), exist_ok=True)
        env["PATH"] = dirgit + ":" + bindir
        self.same([b"import", b"devx", m.bpath(), s.bpath()], env=env, want_code=0)


class Harness(unittest.TestCase):
    """The comparison is not vacuous: different inputs give different results."""

    def test_outputs_differ_when_inputs_do(self):
        go, rs = _bin(GO), _bin(RS)
        a = subprocess.run([go, b"sideways", b"x", b"y", b"z"], capture_output=True)
        b = subprocess.run([rs, b"upwards", b"x", b"y", b"z"], capture_output=True)
        self.assertEqual(a.returncode, b.returncode)
        self.assertNotEqual(a.stderr, b.stderr)


if __name__ == "__main__":
    unittest.main()
