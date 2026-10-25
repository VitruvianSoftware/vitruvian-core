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

"""//tools/secret-scan (Rust) against secret-scan.sh, side by side.

Both run with the real pinned gitleaks and the repo's .gitleaks.toml (handed
over through GITLEAKS / GITLEAKS_CONFIG), against the same throwaway
repositories, and must give the same exit code, stdout and stderr in every
mode (--staged, --range, --unpushed, the default branch scan), for clean and
leaking changes, and for every way the scan can fail to run.
"""

import os
import re
import shutil
import subprocess
import tempfile
import unittest

HERE = os.getcwd()
SH = os.path.join(HERE, os.environ["SECRET_SCAN_SH"])
RS = os.path.join(HERE, os.environ["SECRET_SCAN_RS"])
GITLEAKS = os.path.join(HERE, os.environ["GITLEAKS_BIN"])
RULES = os.path.join(HERE, os.environ["GITLEAKS_RULES"])
BASH = shutil.which("bash")

# A value gitleaks' generic-api-key rule flags, built from pieces so this file
# holds nothing a scan of the repository would flag.
SECRET = "Zq8Lm3Rt" + "7Vx2Kp9W" + "n4Hs6Jd1" + "Fg5Bc0Ya"
SECRET2 = "Ab3De5Fg" + "7Hj9Kl2M" + "n4Pq6Rs8" + "Tv0Wx1Yz"


def normalise(stderr):
    """Sorts the finding lines. gitleaks reports findings in whatever order its
    workers finish, so secret-scan.sh's order differs from run to run (seen
    with the pinned v8.30.1); the Rust port sorts them. Same set, same text."""
    lines = stderr.split(b"\n")
    # bash's own notice when gitleaks dies of a signal ("secret-scan.sh: line
    # N: PID Terminated: 15 ..." on macOS bash 3.2, or bare "Terminated" on
    # Linux GNU bash 5.x): not output a port can or should copy. The verdict
    # lines after it are compared.
    notice = re.compile(rb"^(\S*secret-scan\.sh: line \d+: \d+ |Terminated$)")
    lines = [ln for ln in lines if not notice.match(ln)]
    idx = [
        i for i, ln in enumerate(lines) if ln.startswith(b"  ") and b"  (rule: " in ln
    ]
    for i, ln in zip(idx, sorted(lines[i] for i in idx)):
        lines[i] = ln
    return b"\n".join(lines)


class Parity(unittest.TestCase):
    maxDiff = None

    def setUp(self):
        self.work = os.path.realpath(tempfile.mkdtemp())
        self.home = os.path.join(self.work, "home")
        os.makedirs(self.home)
        self.env = {
            k: v
            for k, v in os.environ.items()
            if k not in ("BUILD_WORKSPACE_DIRECTORY", "GITLEAKS", "GITLEAKS_CONFIG")
        }
        self.env.update(
            HOME=self.home,
            GIT_CONFIG_NOSYSTEM="1",
            GIT_AUTHOR_NAME="t",
            GIT_AUTHOR_EMAIL="t@t",
            GIT_COMMITTER_NAME="t",
            GIT_COMMITTER_EMAIL="t@t",
            GITLEAKS=GITLEAKS,
            GITLEAKS_CONFIG=RULES,
        )
        self.repo = os.path.join(self.work, "repo")
        self.git("init", "-q", "-b", "main", self.repo, cwd=self.work)
        self.git("commit", "-q", "--allow-empty", "-m", "base")
        self.git("update-ref", "refs/remotes/origin/main", "refs/heads/main")

    def tearDown(self):
        shutil.rmtree(self.work)

    def git(self, *args, cwd=None):
        return subprocess.run(
            ["git"] + list(args),
            cwd=cwd or self.repo,
            env=self.env,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    def write(self, name, text):
        path = os.path.join(self.repo, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(text)

    def plant(self, name, secret=SECRET, line=2):
        self.write(name, "first line\n" * (line - 1) + f'api_token = "{secret}"\n')

    def both(self, args, env=None, workspace=None, label=""):
        results = []
        for cmd in ([BASH, SH], [RS]):
            e = dict(self.env)
            if workspace is not False:
                e["BUILD_WORKSPACE_DIRECTORY"] = workspace or self.repo
            e.update(env or {})
            p = subprocess.run(
                cmd + args, cwd=self.work, env=e, capture_output=True, timeout=120
            )
            results.append((p.returncode, p.stdout, normalise(p.stderr)))
        self.assertEqual(results[0], results[1], f"{label} args={args} env={env}")
        for stream in results[0][1:]:
            self.assertNotIn(SECRET.encode(), stream)
            self.assertNotIn(SECRET2.encode(), stream)
        return results[0]

    def test_staged(self):
        self.assertEqual(self.both(["--staged"])[0], 0)
        self.write("ok.txt", "hello\n")
        self.git("add", "ok.txt")
        self.assertEqual(self.both(["--staged"])[0], 0)
        self.plant("leak.txt")
        self.plant("dir/deeper/two.env", SECRET2, line=5)
        self.git("add", "-A")
        self.assertEqual(self.both(["--staged"])[0], 1)
        self.write("allowed.txt", f'api_token = "{SECRET}" # gitleaks:allow\n')
        self.git("reset", "-q")
        self.git("add", "allowed.txt")
        self.assertEqual(self.both(["--staged"])[0], 0)

    def test_branch_range_unpushed(self):
        self.git("checkout", "-q", "-b", "feat/x")
        self.plant("leak.txt")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "leak")
        self.write("more.txt", "more\n")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "clean")
        self.assertEqual(self.both([])[0], 1)
        self.assertEqual(self.both(["--branch"])[0], 1)
        for rng in [
            "HEAD..HEAD",
            "HEAD~1..HEAD",
            "HEAD~2..HEAD",
            "main..feat/x",
            "nope..HEAD",
        ]:
            self.both(["--range", rng], label=rng)
        # level with main: nothing to scan
        self.git("checkout", "-q", "-b", "feat/empty", "main")
        self.assertEqual(self.both([])[0], 0)
        # only origin/main missing, then main used
        self.git("update-ref", "-d", "refs/remotes/origin/main")
        self.git("checkout", "-q", "feat/x")
        self.both([])
        # unpushed, before and after a push
        origin = os.path.join(self.work, "origin.git")
        self.git("init", "-q", "--bare", origin, cwd=self.work)
        self.git("remote", "add", "origin", origin)
        self.both(["--unpushed"])
        self.git("push", "-q", "origin", "main", "feat/x")
        self.assertEqual(self.both(["--unpushed"])[0], 0)
        self.plant("leak2.txt", SECRET2)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "leak2")
        self.assertEqual(self.both(["--unpushed"])[0], 1)

    def test_no_shared_history_and_no_main(self):
        self.git("checkout", "-q", "--orphan", "lonely")
        self.git("commit", "-q", "--allow-empty", "-m", "root")
        self.assertEqual(self.both([])[0], 2)
        self.git("branch", "-q", "-D", "main")
        self.git("update-ref", "-d", "refs/remotes/origin/main")
        self.assertEqual(self.both([])[0], 2)

    def test_arguments(self):
        for args in (
            ["--bogus"],
            ["--range"],
            ["--staged", "--nope"],
            ["-h"],
            ["--help"],
            ["--help", "--bogus"],
            ["--bogus", "--help"],
            ["--staged", "--range", "HEAD..HEAD"],
            ["--range", "HEAD..HEAD", "--staged"],
            ["--unpushed", "--branch"],
            [""],
        ):
            self.both(args, label=" ".join(args))

    def test_cannot_run(self):
        broken = os.path.join(self.work, "broken-gitleaks")
        with open(broken, "w") as f:
            f.write(
                "#!/usr/bin/env bash\necho boom >&2\nfor i in $(seq 1 30); do echo line $i; done\nexit 3\n"
            )
        os.chmod(broken, 0o755)
        noexec = os.path.join(self.work, "noexec")
        with open(noexec, "w") as f:
            f.write("x")
        killed = os.path.join(self.work, "killed-gitleaks")
        with open(killed, "w") as f:
            f.write("#!/usr/bin/env bash\nkill -TERM $$\n")
        os.chmod(killed, 0o755)
        for env in (
            {"GITLEAKS": broken},
            {"GITLEAKS": os.path.join(self.work, "nope")},
            {"GITLEAKS": noexec},
            {"GITLEAKS": killed},
            {"GITLEAKS_CONFIG": os.path.join(self.work, "nope.toml")},
            {"GITLEAKS_CONFIG": self.work},
        ):
            # (the default branch scan on main stops before gitleaks: nothing to scan)
            for args in (["--staged"], ["--range", "HEAD..HEAD"], []):
                rc = self.both(args, env=env)[0]
                self.assertEqual(
                    rc,
                    0
                    if args == []
                    and "GITLEAKS_CONFIG" not in env
                    and env["GITLEAKS"] != os.path.join(self.work, "nope")
                    and env["GITLEAKS"] != noexec
                    else 2,
                    (env, args),
                )
        bad_rules = os.path.join(self.work, "bad.toml")
        with open(bad_rules, "w") as f:
            f.write("this is [not toml\n")
        self.assertEqual(
            self.both(["--staged"], env={"GITLEAKS_CONFIG": bad_rules})[0], 2
        )

    def test_not_a_repository(self):
        plain = os.path.join(self.work, "plain")
        os.makedirs(plain)
        self.assertEqual(self.both(["--staged"], workspace=plain)[0], 2)
        self.assertEqual(
            self.both(["--staged"], workspace=os.path.join(self.work, "missing"))[0], 2
        )
        # No BUILD_WORKSPACE_DIRECTORY: the tree is found from the working directory.
        self.both(["--staged"], workspace=False)


if __name__ == "__main__":
    unittest.main()
