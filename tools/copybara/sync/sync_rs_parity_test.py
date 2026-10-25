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

"""sync, the Rust port, against the Go original: same exit code, stdout,
stderr and the same docker invocations, byte for byte, on every input here.

    bazel test //tools/copybara/sync:sync_rs_parity_test

Both binaries run with a fake `docker` first on PATH. It logs every argument
it gets (and the content of the config file mounted at /root/copy.bara.sky),
writes to stdout and stderr, and exits with a scripted code per call, or is
killed by a signal. The cases:
  * every scenario in main_test.go: exit 0/4 success, export without retry,
    import retried up to three times (the real 10s and 15s backoffs), the
    unknown direction, docker args, --options, import_pr's shape;
  * usage errors, --options edge cases, non-UTF-8 components;
  * where the workspace comes from: BUILD_WORKSPACE_DIRECTORY, then
    GITHUB_WORKSPACE, then the current directory (via $PWD when it names it);
  * docker missing, found only relatively, not executable, not a program,
    killed by a signal;
  * import_pr: PR numbers that are not digits, a missing or unreadable
    copy.bara.sky, an unusable TMPDIR, and the temp config being removed.

The import_pr temp file name is random; it is the only thing normalised.
"""

import concurrent.futures
import os
import re
import shutil
import stat
import subprocess
import tempfile
import time
import unittest

GO = os.environ.get("SYNC_GO", "")
RS = os.environ.get("SYNC_RS", "")

FAKE_DOCKER = r"""#!/bin/sh
state="$FAKE_DOCKER_DIR/calls"
n=$(@CAT@ "$state" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" > "$state"
{
  echo "call $n"
  for a in "$@"; do printf 'arg[%s]\n' "$a"; done
  echo "GITHUB_TOKEN=${GITHUB_TOKEN-unset}"
  for a in "$@"; do
    case "$a" in
      *:/root/copy.bara.sky)
        f=${a%:/root/copy.bara.sky}
        if [ -f "$f" ]; then echo "cfg:"; @CAT@ "$f"; @LS@ -l "$f" | @CUT@ -c1-10; fi ;;
    esac
  done
} >> "$FAKE_DOCKER_DIR/log"
echo "docker stdout $n"
echo "docker stderr $n" >&2
code=$(echo "$FAKE_DOCKER_CODES" | @CUT@ -d, -f"$n")
[ -z "$code" ] && code=$(echo "$FAKE_DOCKER_CODES" | @AWK@ -F, '{print $NF}')
if [ "$code" = kill ]; then kill -9 $$; fi
exit "$code"
"""

TEMP_RE = re.compile(rb"copy\.bara\.[0-9]+\.sky")


def _bin(path):
    if not path:
        raise unittest.SkipTest("run this under bazel test")
    return os.path.abspath(path)


def norm(b):
    return TEMP_RE.sub(b"copy.bara.N.sky", b)


class Parity(unittest.TestCase):
    def setUp(self):
        self.go = _bin(GO)
        self.rs = _bin(RS)
        self.tmp = tempfile.mkdtemp(dir=os.environ.get("TEST_TMPDIR"))
        self.bindir = os.path.join(self.tmp, "bin")
        os.makedirs(self.bindir)
        docker = os.path.join(self.bindir, "docker")
        script = FAKE_DOCKER
        for tool in ("cat", "ls", "cut", "awk"):
            script = script.replace(
                "@%s@" % tool.upper(), shutil.which(tool, path="/usr/bin:/bin") or tool
            )
        with open(docker, "w") as f:
            f.write(script)
        os.chmod(docker, 0o755)
        self.ws = self.workspace("ws")
        self.n = 0

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def workspace(
        self,
        name,
        cfg=b'x = "import-pr-@@PR_NUMBER@@"\ny = "@@PR_NUMBER@@@@PR_NUMBER@@"\n',
    ):
        ws = os.path.join(self.tmp, name)
        os.makedirs(os.path.join(ws, "tools", "copybara"))
        if cfg is not None:
            with open(
                os.path.join(ws, "tools", "copybara", "copy.bara.sky"), "wb"
            ) as f:
                f.write(cfg)
        return ws

    def env(self, **kw):
        env = {
            "PATH": self.bindir + ":/usr/bin:/bin",
            "HOME": "/home/tester",
            "BUILD_WORKSPACE_DIRECTORY": self.ws,
            "GITHUB_TOKEN": "tok-123",
            "FAKE_DOCKER_CODES": "0",
        }
        for k, v in kw.items():
            if v is None:
                env.pop(k, None)
            else:
                env[k] = v
        return env

    def run_one(self, binary, args, env, cwd):
        self.n += 1
        d = os.path.join(self.tmp, "run%d" % self.n)
        tmpdir = os.path.join(d, "tmp")
        os.makedirs(tmpdir)
        env = dict(env)
        env["FAKE_DOCKER_DIR"] = d
        env.setdefault("TMPDIR", tmpdir)
        p = subprocess.run(
            [binary, *args], env=env, cwd=cwd or self.tmp, capture_output=True
        )
        try:
            with open(os.path.join(d, "log"), "rb") as f:
                log = f.read()
        except FileNotFoundError:
            log = b""
        left = sorted(os.listdir(tmpdir))
        run = os.fsencode(d)

        def n(b):
            return norm(b.replace(run, b"<RUN>"))

        return (p.returncode, n(p.stdout), n(p.stderr), n(log), left)

    def same(self, args, want_code=None, cwd=None, **envkw):
        env = self.env(**envkw)
        go = self.run_one(self.go, args, env, cwd)
        rs = self.run_one(self.rs, args, env, cwd)
        self.assertEqual(go, rs, "args=%r env=%r" % (args, envkw))
        if want_code is not None:
            self.assertEqual(go[0], want_code, "args=%r: %r" % (args, go))
        self.assertEqual(go[4], [], "temp config left behind: %r" % (go,))
        return go

    # --- main_test.go -------------------------------------------------------

    def test_exit_codes_without_retry(self):
        for d in (b"export", b"import"):
            for codes, want in (("0", 0), ("4", 0)):
                self.same([d, b"devx"], want, FAKE_DOCKER_CODES=codes)
        for codes, want in (
            ("1", 1),
            ("2", 2),
            ("3", 3),
            ("5", 5),
            ("255", 255),
            ("kill", 255),
        ):
            r = self.same([b"export", b"devx"], want, FAKE_DOCKER_CODES=codes)
            self.assertEqual(r[3].count(b"call "), 1)

    def test_import_retries(self):
        # Each binary sleeps for real (10s, then 15s); run the cases at once.
        cases = [
            ("1,0", 0, 2),
            ("1,4", 0, 2),
            ("1,1,1", 1, 3),
            ("2,3,4", 0, 3),
            ("7,kill,9", 9, 3),
        ]

        def timed(binary, env):
            t = time.monotonic()
            r = self.run_one(binary, [b"import", b"mcp-slack"], env, None)
            return r, time.monotonic() - t

        def one(case):
            env = self.env(FAKE_DOCKER_CODES=case[0])
            with concurrent.futures.ThreadPoolExecutor(2) as inner:
                go = inner.submit(timed, self.go, env)
                rs = inner.submit(timed, self.rs, env)
                return case, go.result(), rs.result()

        # The backoff is not in the output, so time it: 10s before the second
        # attempt, 15s before the third.
        backoff = {2: 10.0, 3: 25.0}
        with concurrent.futures.ThreadPoolExecutor(len(cases)) as pool:
            for (codes, want, calls), (go, tgo), (rs, trs) in pool.map(one, cases):
                self.assertEqual(go, rs, codes)
                self.assertEqual(go[0], want, (codes, go))
                self.assertEqual(go[3].count(b"call "), calls, codes)
                for t in (tgo, trs):
                    self.assertGreaterEqual(t, backoff[calls], (codes, tgo, trs))
                    self.assertLess(t, backoff[calls] + 4.0, (codes, tgo, trs))

    def test_usage_and_directions(self):
        for args in ([], [b"export"], [b"import_pr"], [b"import_pr", b"devx"]):
            self.same(args, 2)
        for d in (b"sideways", b"", b"Export", b"import_pr2", b"\xff"):
            self.same([d, b"devx"], 2)
            self.same([d, b"devx", b"--options", b"x"], 2)

    def test_docker_args_and_options(self):
        for extra in (
            [],
            [b"--options", b"--force --ignore-noop"],
            [b"--options"],
            [b"--options", b"a", b"--options", b"b"],
            [b"--options", b"--options", b"c"],
            [b"x", b"--options", b""],
            [b"--options=foo"],
            [b"--options", b"caf\xc3\xa9 \xff"],
        ):
            for d in (b"export", b"import"):
                self.same([d, b"mcp-slack", *extra], 0)
        for comp in (
            b"nexus-agent",
            b"a-b-c",
            b"",
            b"-",
            b"bad\xffname",
            "é-x".encode(),
        ):
            self.same([b"export", comp], 0)

    def test_where_the_workspace_comes_from(self):
        other = self.workspace("other")
        link = os.path.join(self.tmp, "wslink")
        os.symlink(self.ws, link)
        self.same(
            [b"export", b"devx"],
            0,
            BUILD_WORKSPACE_DIRECTORY=self.ws,
            GITHUB_WORKSPACE=other,
        )
        self.same(
            [b"export", b"devx"],
            0,
            BUILD_WORKSPACE_DIRECTORY="",
            GITHUB_WORKSPACE=other,
        )
        self.same(
            [b"export", b"devx"], 0, BUILD_WORKSPACE_DIRECTORY=None, GITHUB_WORKSPACE=""
        )
        for pwd in (None, self.ws, link, other, "relative/path", "/nonexistent", ""):
            self.same(
                [b"export", b"devx"],
                0,
                cwd=self.ws,
                BUILD_WORKSPACE_DIRECTORY=None,
                GITHUB_WORKSPACE=None,
                PWD=pwd,
            )
        self.same(
            [b"export", b"devx"], 0, cwd=link, BUILD_WORKSPACE_DIRECTORY=None, PWD=link
        )
        self.same([b"export", b"devx"], 0, HOME=None)
        self.same([b"export", b"devx"], 0, HOME="")
        self.same([b"export", b"devx"], 0, BUILD_WORKSPACE_DIRECTORY="/ws/with space/")

    def test_docker_that_cannot_run(self):
        self.same([b"export", b"devx"], 1, PATH="/nonexistent")
        self.same([b"export", b"devx"], 1, PATH=None)
        self.same([b"export", b"devx"], 1, PATH="")
        # Found only through a relative PATH entry: os/exec refuses it.
        self.same([b"import", b"devx"], 1, cwd=self.tmp, PATH="bin")
        self.same([b"import", b"devx"], 1, cwd=self.tmp, PATH=":/usr/bin")
        # Not executable: skipped, so not found.
        noexec = os.path.join(self.tmp, "noexec")
        os.makedirs(noexec)
        shutil.copy(os.path.join(self.bindir, "docker"), os.path.join(noexec, "docker"))
        os.chmod(os.path.join(noexec, "docker"), 0o644)
        self.same([b"export", b"devx"], 1, PATH=noexec)
        # A directory named docker is skipped; the next entry is used.
        dirdocker = os.path.join(self.tmp, "dirdocker")
        os.makedirs(os.path.join(dirdocker, "docker"))
        self.same([b"export", b"devx"], 0, PATH=dirdocker + ":" + self.bindir)
        # Executable but not a program.
        garbage = os.path.join(self.tmp, "garbage")
        os.makedirs(garbage)
        with open(os.path.join(garbage, "docker"), "wb") as f:
            f.write(b"\x00\x01\x02not a program\n")
        os.chmod(os.path.join(garbage, "docker"), 0o755)
        self.same([b"export", b"devx"], 1, PATH=garbage)
        self.same([b"import_pr", b"devx", b"7"], 1, PATH=garbage)

    # --- import_pr ----------------------------------------------------------

    def test_import_pr(self):
        for codes, want in (("0", 0), ("4", 0), ("1", 1), ("3", 3), ("kill", 255)):
            self.same(
                [b"import_pr", b"mcp-slack", b"123"], want, FAKE_DOCKER_CODES=codes
            )
        self.same([b"import_pr", b"devx", b"5", b"--options", b"--force"], 0)
        self.same([b"import_pr", b"devx", b"5", b"--options"], 0)
        self.same([b"import_pr", b"devx", b"0042"], 0, GITHUB_TOKEN=None)
        self.same([b"import_pr", b"devx", b"9" * 30], 0)
        for pr in (
            b"",
            b"12x",
            b"-1",
            b"+1",
            b" 1",
            b"1\n",
            "１２".encode(),
            b"\xff",
            b'1"\\',
            b"\x07\t",
        ):
            self.same([b"import_pr", b"devx", pr], 2)

    def test_import_pr_config_problems(self):
        nocfg = self.workspace("nocfg", cfg=None)
        self.same([b"import_pr", b"devx", b"5"], 1, BUILD_WORKSPACE_DIRECTORY=nocfg)
        self.same(
            [b"import_pr", b"devx", b"5"], 1, BUILD_WORKSPACE_DIRECTORY=nocfg + "//./"
        )
        dircfg = self.workspace("dircfg", cfg=None)
        os.makedirs(os.path.join(dircfg, "tools", "copybara", "copy.bara.sky"))
        self.same([b"import_pr", b"devx", b"5"], 1, BUILD_WORKSPACE_DIRECTORY=dircfg)
        empty = self.workspace("emptycfg", cfg=b"")
        self.same([b"import_pr", b"devx", b"5"], 0, BUILD_WORKSPACE_DIRECTORY=empty)
        binary = self.workspace("bincfg", cfg=b"\xff\x00@@PR_NUMBER@\xfe@@PR_NUMBER@@@")
        self.same([b"import_pr", b"devx", b"8"], 0, BUILD_WORKSPACE_DIRECTORY=binary)
        self.same([b"import_pr", b"devx", b"5"], 1, TMPDIR="/nonexistent/tmp")
        trailing = os.path.join(self.tmp, "trailing") + "/"
        os.makedirs(trailing)
        r = self.same([b"import_pr", b"devx", b"5"], 0, TMPDIR=trailing)
        self.assertNotIn(b"//copy.bara", r[3])
        self.assertEqual(os.listdir(trailing), [])
        ro = os.path.join(self.tmp, "ro")
        os.makedirs(ro)
        os.chmod(ro, stat.S_IRUSR | stat.S_IXUSR)
        try:
            if not os.access(ro, os.W_OK):
                self.same([b"import_pr", b"devx", b"5"], 1, TMPDIR=ro)
        finally:
            os.chmod(ro, 0o755)
        # Workspace from the current directory.
        self.same(
            [b"import_pr", b"devx", b"6"],
            0,
            cwd=self.ws,
            BUILD_WORKSPACE_DIRECTORY=None,
            PWD=self.ws,
        )


class Harness(unittest.TestCase):
    """The comparison is not vacuous: the fake docker's log tells runs apart."""

    def test_logs_differ_when_inputs_do(self):
        p = Parity("test_usage_and_directions")
        p.setUp()
        try:
            env = p.env()
            a = p.run_one(p.go, [b"export", b"devx"], env, None)
            b = p.run_one(p.rs, [b"export", b"homelab"], env, None)
            self.assertEqual(a[0], b[0])
            self.assertNotEqual(a[3], b[3])
        finally:
            p.tearDown()


if __name__ == "__main__":
    unittest.main()
