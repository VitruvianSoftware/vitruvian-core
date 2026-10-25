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

"""cluster_cmd.sh against the Rust binary, side by side.

Both run every op with the same stand-in kubectl, which records each call
(arguments, KUBECONFIG, working directory) and answers the diagnostics'
queries with tables the scenario sets: busy and idle clusters, ties, blank
and unterminated lines, PV tables with odd rows, failing calls. Exit status,
stdout, stderr and the record of calls must match byte for byte, after the
program's own path is replaced by <prog>.

PARITY_BASH picks the bash that runs the script (default: bash on PATH).
cluster_cmd.sh has no #! line; //tools/cluster's sh_binary runs it with bash.
"""

import os
import shutil
import subprocess
import tempfile
import unittest

HERE = os.getcwd()
SH = os.path.join(HERE, os.environ["CLUSTER_SH"])
RS = os.path.join(HERE, os.environ["CLUSTER_RS"])
BASH = os.environ.get("PARITY_BASH") or shutil.which("bash") or "bash"
BASH_MAJOR = int(
    subprocess.run(
        [BASH, "-c", 'echo "${BASH_VERSINFO[0]}"'], capture_output=True, text=True
    ).stdout.strip()
)

OPS = [
    "kubectl",
    "cordon",
    "uncordon",
    "drain",
    "delete-node",
    "label-node",
    "balance",
    "placement",
    "minio-status",
]

KUBECTL = r"""#!/bin/sh
{
  printf 'kubectl'
  for a in "$@"; do printf ' [%s]' "$a"; done
  printf ' KUBECONFIG=%s cwd=%s PWD=%s OLDPWD=%s\n' "${KUBECONFIG-unset}" "$(pwd -P)" "${PWD-unset}" "${OLDPWD-unset}"
} >>"$LOG"
echo "kubectl stderr: $1 $2 $3" >&2
case "$*" in
  *"get pods -A"*) printf '%b' "${PODS_A-}"; exit "${RC_PODS_A:-0}" ;;
  *"get pods -o wide"*) echo "NAME READY STATUS"; exit "${RC_WIDE:-0}" ;;
  *"get pv"*) printf '%b' "${PV-}"; exit "${RC_PV:-0}" ;;
  *"get pods -o name"*) printf '%b' "${NAMES-}"; exit "${RC_NAMES:-0}" ;;
  *" exec "*) echo "mc says hi"; exit "${RC_EXEC:-0}" ;;
esac
echo "passthrough out"
exit "${RC:-0}"
"""

PV = (
    "PV                CLAIM       NS      PINNED_NODE\\n"
    "pvc-1             data-0      minio   nuc9\\n"
    "pvc-2             cache       other   nuc8\\n"
    "pvc-3             data-1      minio   <none>\\n"
    "short\\n"
    "pvc-4 x 1.0 nuc7\\n"
    "pvc-5 x 1 nuc6\\n"
)


class Parity(unittest.TestCase):
    maxDiff = None

    def setUp(self):
        self.work = os.path.realpath(tempfile.mkdtemp())
        self.bin = os.path.join(self.work, "bin")
        self.ws = os.path.join(self.work, "ws")
        self.home = os.path.join(self.work, "home")
        for d in (self.bin, self.ws, self.home):
            os.makedirs(d)
        k = os.path.join(self.bin, "kubectl")
        with open(k, "w") as f:
            f.write(KUBECTL)
        os.chmod(k, 0o755)
        self.log = os.path.join(self.work, "log")
        self.count = 0

    def tearDown(self):
        shutil.rmtree(self.work)

    def run_one(self, cmd, prog, args, env):
        open(self.log, "w").close()
        full = {
            "PATH": self.bin + ":/usr/bin:/bin",
            "HOME": self.home,
            "LOG": self.log,
            "BUILD_WORKSPACE_DIRECTORY": self.ws,
        }
        full.update(env)
        full = {k: v for k, v in full.items() if v is not None}
        p = subprocess.run(
            cmd + list(args), env=full, cwd=self.work, capture_output=True
        )
        with open(self.log, "rb") as f:
            record = f.read()

        def norm(b):
            return b.replace(prog.encode(), b"<prog>")

        return p.returncode, norm(p.stdout), norm(p.stderr), record

    def both(self, args, env=None, expect_rc=None, bash5_only=False):
        if bash5_only and BASH_MAJOR < 4:
            print(f"skip under bash {BASH_MAJOR}: {args} {env}")
            return None
        self.count += 1
        got_sh = self.run_one([BASH, SH], SH, args, env or {})
        got_rs = self.run_one([RS], RS, args, env or {})
        self.assertEqual(got_sh, got_rs, f"{args} {env}")
        if expect_rc is not None:
            self.assertEqual(got_rs[0], expect_rc, got_rs)
        return got_rs

    def test_passthrough_ops(self):
        odd = ["nuc9", "", "two words", "*", "--force", "-n", "kube-system", "$HOME"]
        for op in (
            "kubectl",
            "cordon",
            "uncordon",
            "drain",
            "delete-node",
            "label-node",
            "placement",
        ):
            self.both([op], expect_rc=0)
            self.both([op] + odd, expect_rc=0)
            self.both([op, "x"], {"RC": "5"}, expect_rc=5)

    def test_environment(self):
        for env in (
            {"KUBECONFIG": "/k/config.yaml"},
            {"KUBECONFIG": ""},
            {"KUBE_CONTEXT": "lab"},
            {"KUBE_CONTEXT": ""},
            {"HOME": None, "KUBECONFIG": "/k"},
            {"HOME": None},
            {"HOME": ""},
            {"BUILD_WORKSPACE_DIRECTORY": None},
            {"BUILD_WORKSPACE_DIRECTORY": ""},
            {"BUILD_WORKSPACE_DIRECTORY": os.path.join(self.work, "gone")},
            {"BUILD_WORKSPACE_DIRECTORY": self.log},
            {"PATH": "/usr/bin:/bin"},
        ):
            self.both(["cordon", "nuc9"], env)

    def test_workspace_through_a_symlink(self):
        link = os.path.join(self.work, "link")
        os.symlink(self.ws, link)
        self.both(["cordon", "x"], {"BUILD_WORKSPACE_DIRECTORY": link}, expect_rc=0)
        self.both(["cordon", "x"], {"BUILD_WORKSPACE_DIRECTORY": link + "/../link//./"})
        self.both(["cordon", "x"], {"BUILD_WORKSPACE_DIRECTORY": "ws"})
        self.both(["cordon", "x"], {"BUILD_WORKSPACE_DIRECTORY": "link/"})
        self.both(
            ["minio-status"], {"BUILD_WORKSPACE_DIRECTORY": link, "NAMES": "pod/a\\n"}
        )
        self.both(["cordon", "x"], {"PWD": link, "BUILD_WORKSPACE_DIRECTORY": link})
        self.both(["cordon", "x"], {"PWD": "/nonexistent", "OLDPWD": "/y"})

    def test_kubectl_not_executable(self):
        # bash's `command -v` counts a non-executable file; the exec then
        # fails. bash 3.2 exits 1 there and bash 5 exits 126 (the port's).
        other = os.path.join(self.work, "other")
        os.makedirs(other)
        with open(os.path.join(other, "kubectl"), "w") as f:
            f.write("#!/bin/sh\n")
        self.both(["cordon", "x"], {"PATH": other + ":/usr/bin:/bin"}, bash5_only=True)
        self.both(["cordon", "x"], {"PATH": other + ":" + self.bin + ":/usr/bin:/bin"})

    def test_op_selection(self):
        self.both([], expect_rc=1)
        self.both([""], expect_rc=1)
        self.both(["bogus"], expect_rc=2)
        self.both(["bogus", "a", "b"], expect_rc=2)
        self.both(["Cordon"], expect_rc=2)
        self.both(["bogus"], {"PATH": "/usr/bin:/bin"}, expect_rc=1)

    def test_balance(self):
        for pods in (
            "nuc9\\nnuc8\\nnuc9\\nnuc7\\nnuc9\\nnuc8\\n",
            "",
            "\\n",
            "nuc9",
            "nuc9\\nnuc9",
            "b\\na\\nc\\n",
            "<none>\\nnuc1\\n\\n\\nnuc1\\n",
            "n\\n" * 12 + "m\\n" * 3 + "z\\n" * 3 + "a\\n",
            "with space\\nwith space\\nwith  space\\n",
            "Zed\\nalpha\\nBeta\\n_x\\n-y\\n",
        ):
            self.both(["balance"], {"PODS_A": pods}, expect_rc=0)
        self.both(
            ["balance"], {"PODS_A": "a\\na\\nb\\n", "RC_PODS_A": "3"}, expect_rc=3
        )
        self.both(["balance", "ignored", "args"], {"PODS_A": "a\\n"}, expect_rc=0)

    def test_minio_status(self):
        names = "pod/minio-0\\npod/minio-1\\n"
        self.both(["minio-status"], {"PV": PV, "NAMES": names}, expect_rc=0)
        self.both(
            ["minio-status"],
            {"PV": PV, "NAMES": names, "MINIO_NS": "other"},
            expect_rc=0,
        )
        self.both(
            ["minio-status"], {"PV": PV, "NAMES": names, "MINIO_NS": ""}, expect_rc=0
        )
        self.both(
            ["minio-status"], {"PV": PV, "NAMES": names, "MINIO_NS": "1"}, expect_rc=0
        )
        self.both(
            ["minio-status"], {"PV": PV, "NAMES": names, "MINIO_NS": "PINNED_NODE"}
        )
        self.both(["minio-status"], {"PV": "", "NAMES": ""}, expect_rc=0)
        self.both(["minio-status"], {"PV": "H\\nr a minio z", "NAMES": "\\n\\npod/m-0"})
        self.both(["minio-status"], {"PV": PV, "NAMES": "minio-0\\n"})
        self.both(
            ["minio-status"], {"PV": PV, "NAMES": names, "RC_EXEC": "1"}, expect_rc=0
        )
        self.both(
            ["minio-status"], {"PV": PV, "NAMES": names, "RC_NAMES": "1"}, expect_rc=0
        )
        self.both(
            ["minio-status"], {"PV": PV, "NAMES": "", "RC_NAMES": "1"}, expect_rc=0
        )
        self.both(
            ["minio-status"], {"PV": PV, "NAMES": names, "RC_WIDE": "4"}, expect_rc=4
        )
        self.both(
            ["minio-status"], {"PV": PV, "NAMES": names, "RC_PV": "5"}, expect_rc=5
        )
        self.both(["minio-status", "extra"], {"PV": PV, "NAMES": names})

    def test_harness_sees_a_difference(self):
        a = self.run_one([BASH, SH], SH, ["cordon", "a"], {})
        b = self.run_one([RS], RS, ["cordon", "b"], {})
        self.assertNotEqual(a, b)


if __name__ == "__main__":
    unittest.main(verbosity=2)
