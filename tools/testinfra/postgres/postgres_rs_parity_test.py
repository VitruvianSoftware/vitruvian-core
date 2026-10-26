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

"""run-postgres.sh / check-postgres.sh against the Rust binaries, side by side.

Each scenario runs both implementations with the same stand-in initdb,
postgres and pg_isready (which record their arguments, environment and
standard input), the same environment and the same working directory. Exit
status, stdout, stderr and the record must match byte for byte, after the
program's own path is replaced by <prog> (bash names the script, the port
names itself, in the same place).

PARITY_BASH picks the bash that runs the scripts (default: bash on PATH).
bash 3.2 (macOS) and bash 5 (Linux) give different exit statuses for a
program path that does not exist (1 against 127); the port follows bash 5,
so those scenarios only run under bash 4 or later.
"""

import os
import shutil
import subprocess
import tempfile
import unittest

HERE = os.getcwd()
RUN_SH = os.path.join(HERE, os.environ["RUN_POSTGRES_SH"])
CHECK_SH = os.path.join(HERE, os.environ["CHECK_POSTGRES_SH"])
RUN_RS = os.path.join(HERE, os.environ["RUN_POSTGRES_RS"])
CHECK_RS = os.path.join(HERE, os.environ["CHECK_POSTGRES_RS"])
BASH = os.environ.get("PARITY_BASH") or shutil.which("bash") or "bash"
BASH_MAJOR = int(
    subprocess.run(
        [BASH, "-c", 'echo "${BASH_VERSINFO[0]}"'], capture_output=True, text=True
    ).stdout.strip()
)

STUB = """#!/bin/sh
{
  printf '%s' "NAME"
  for a in "$@"; do printf ' [%s]' "$a"; done
  printf ' LC_ALL=%s LANG=%s cwd=%s\\n' "${LC_ALL-unset}" "${LANG-unset}" "$(pwd)"
} >>"$LOG"
echo "NAME says hello on stdout"
echo "NAME says hello on stderr" >&2
exit "${NAME_RC:-0}"
"""


def strip_locale_notice(stderr):
    """bash's own startup notice when the environment names a locale the
    system lacks ("bash: warning: setlocale: LC_ALL: cannot change locale"),
    printed before the script runs a line: not the script's output."""
    return b"".join(
        ln
        for ln in stderr.splitlines(keepends=True)
        if b"warning: setlocale: " not in ln
    )


class Parity(unittest.TestCase):
    maxDiff = None

    def setUp(self):
        self.work = os.path.realpath(tempfile.mkdtemp())
        self.bin = os.path.join(self.work, "bin")
        os.makedirs(self.bin)
        for name in ("initdb", "postgres", "pg_isready"):
            path = os.path.join(self.bin, name)
            with open(path, "w") as f:
                f.write(
                    STUB.replace("NAME_RC", name.upper() + "_RC").replace("NAME", name)
                )
            os.chmod(path, 0o755)
        noexec = os.path.join(self.bin, "noexec")
        with open(noexec, "w") as f:
            f.write("#!/bin/sh\n")
        os.chmod(noexec, 0o644)
        self.log = os.path.join(self.work, "log")
        self.count = 0

    def tearDown(self):
        shutil.rmtree(self.work)

    def run_one(self, cmd, prog, args, env):
        open(self.log, "w").close()
        full = {
            "PATH": self.bin + ":/usr/bin:/bin",
            "HOME": self.work,
            "LOG": self.log,
        }
        full.update(env)
        p = subprocess.run(
            cmd + list(args), env=full, cwd=self.work, capture_output=True
        )
        with open(self.log, "rb") as f:
            record = f.read()

        def norm(b):
            return b.replace(prog.encode(), b"<prog>")

        return p.returncode, norm(p.stdout), norm(strip_locale_notice(p.stderr)), record

    def both(self, which, args, env=None, bash5_only=False):
        if bash5_only and BASH_MAJOR < 4:
            print(f"skip under bash {BASH_MAJOR}: {which} {args}")
            return
        self.count += 1
        sh, rs = (RUN_SH, RUN_RS) if which == "run" else (CHECK_SH, CHECK_RS)
        got_sh = self.run_one([BASH, sh], sh, args, env or {})
        got_rs = self.run_one([rs], rs, args, env or {})
        self.assertEqual(got_sh, got_rs, f"{which} {args} {env}")
        return got_rs

    def b(self, name):
        return os.path.join(self.bin, name)

    def test_run(self):
        tmp = os.path.join(self.work, "tmp")
        good = [self.b("initdb"), self.b("postgres"), "5433", tmp]
        rc, _, _, rec = self.both("run", good)
        self.assertEqual(rc, 0)
        self.assertIn(b"postgres [-D]", rec)
        self.both("run", good, {"POSTGRES_RC": "9"})
        self.both("run", good, {"INITDB_RC": "3"})
        self.both("run", good, {"LC_ALL": "en_US.UTF-8", "LANG": "fr_FR"})
        self.both("run", good + ["extra", "args"])
        self.both("run", [self.b("initdb"), self.b("postgres"), "", ""])
        self.both("run", [self.b("initdb"), self.b("postgres"), "5 4", "a b/c"])
        # Found on PATH by name, as bash does.
        self.both("run", ["initdb", "postgres", "1", tmp])
        self.both("run", ["no-such-initdb", "postgres", "1", tmp])
        self.both("run", ["initdb", "no-such-postgres", "1", tmp])
        self.both(
            "run", [self.b("gone"), self.b("postgres"), "1", tmp], bash5_only=True
        )
        self.both("run", [self.b("initdb"), self.b("gone"), "1", tmp], bash5_only=True)
        self.both(
            "run", [self.b("noexec"), self.b("postgres"), "1", tmp], bash5_only=True
        )
        for n in range(4):
            self.both("run", good[:n])

    def test_check(self):
        good = [self.b("pg_isready"), "5433"]
        rc, _, _, rec = self.both("check", good)
        self.assertEqual(rc, 0)
        self.assertIn(b"[-h] [127.0.0.1]", rec)
        self.both("check", good, {"PG_ISREADY_RC": "2"})
        self.both("check", good + ["ignored"])
        self.both("check", ["pg_isready", ""])
        self.both("check", ["no-such-isready", "1"])
        self.both("check", [self.b("gone"), "1"], bash5_only=True)
        for n in range(2):
            self.both("check", good[:n])

    def test_planted_difference_is_seen(self):
        # The harness itself: a different argument must make the records differ.
        a = self.run_one([BASH, CHECK_SH], CHECK_SH, [self.b("pg_isready"), "1"], {})
        b = self.run_one([CHECK_RS], CHECK_RS, [self.b("pg_isready"), "2"], {})
        self.assertNotEqual(a, b)


if __name__ == "__main__":
    unittest.main(verbosity=2)
