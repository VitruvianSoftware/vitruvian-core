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
"""The platform-e2e runner, the Rust port, against runner.sh. Each runs from
its own copy of a small workspace -- MODULE.bazel at the top,
tools/platform-e2e/runner (the script, or the binary) and fake tier
scripts beside it -- and the two are compared on exit code, stdout, stderr
and the files left behind, with durations normalised.

    bazel test //tools/platform-e2e:runner_rs_parity_test
"""

import os
import shutil
import subprocess
import sys

sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shell-compat")
)
from parity_harness import Case, Harness, need_env, write, write_exec  # noqa: E402

SH = os.path.abspath(need_env("RUNNER_SH"))
RS = os.path.abspath(need_env("RUNNER_RS"))

_PY = shutil.which("python3") or sys.executable
BASE_PATH = os.path.dirname(_PY) + ":/usr/bin:/bin:/usr/sbin:/sbin"

TIERS = (
    "tier1_feature_test.sh",
    "tier2_boundary_test.sh",
    "tier3_combination_test.sh",
    "tier4_workload_test.sh",
)

# A fake tier: prints $T<n>_OUT (printf %b) and exits $T<n>_RC; it logs
# where it ran and what it was given.
TIER = r"""#!/usr/bin/env bash
n=%d
printf 'tier %%s ran in %%s args=%%s\n' "$n" "$PWD" "$#" >>"$STATE/tiers.log"
eval "out=\${T${n}_OUT-ok 1 - default\\nok 2 - default}"
eval "rc=\${T${n}_RC:-0}"
printf '%%b' "$out"
[ -n "${T_STDERR:-}" ] && printf '%%b' "$T_STDERR" >&2
[ "$rc" = kill ] && kill -9 $$
exit "$rc"
"""

# The bash the harness runs the script with: before 4.4 an empty array
# under `set -u` is an error, which the port does not reproduce.
_BV = subprocess.run(
    [
        shutil.which("bash") or "/bin/bash",
        "-c",
        "echo ${BASH_VERSINFO[0]} ${BASH_VERSINFO[1]}",
    ],
    capture_output=True,
    text=True,
).stdout.split()
EMPTY_ARRAY_OK = (int(_BV[0]), int(_BV[1])) >= (4, 4)


def workspace(marker="MODULE.bazel", tiers=TIERS, extra=None):
    def setup(root):
        impl = os.path.basename(root)
        os.makedirs(root + "/state")
        if marker:
            write(root + "/" + marker, "")
        d = root + "/tools/platform-e2e"
        os.makedirs(d, exist_ok=True)
        shutil.copy(SH if impl == "sh" else RS, d + "/runner")
        os.chmod(d + "/runner", 0o755)
        for i, t in enumerate(TIERS, 1):
            if t in tiers:
                write_exec(d + "/" + t, TIER % i)
        if extra:
            extra(root)

    return setup


class RunnerHarness(Harness):
    """Runs <sandbox>/<via> in each sandbox: the script under bash, the
    binary directly, both named `runner` so usage names them alike."""

    def check_via(self, case, via="tools/platform-e2e/runner"):
        n = self.count + 1
        self.script = os.path.join(self.base, "%03d" % n, "sh", via)
        self.binary = os.path.join(self.base, "%03d" % n, "rs", via)
        self.check(case)


TIME = [
    (rb"\| \d+ +ms \|", b"| <N>ms |"),
    (rb"\d+ms", b"<N>ms"),
    (rb'"duration_ms": \d+', b'"duration_ms": <N>'),
]

# The harness starts each run from PATH, HOME and TMPDIR alone, so
# BUILD_WORKSPACE_DIRECTORY is unset unless a case sets it.
ENV = {"STATE": "{root}/state"}


SKIPPED = set()


def case(name, setup=None, args=None, env=None, skip=False, **kw):
    e = dict(ENV)
    e.update(env or {})
    c = Case(
        name=name,
        args=args or [],
        env=e,
        setup=setup or workspace(),
        normalise=TIME,
        # The program under test: the script in one sandbox, the binary in
        # the other.
        # macOS's /usr/bin/python3 shim (the script times itself with
        # python3) caches under $HOME/Library; the port runs no python.
        ignore=[r"tools/platform-e2e/runner$", r"home/Library(/|$)"],
        **kw,
    )
    if skip:
        SKIPPED.add(name)
    return c


FAIL2 = {"T2_OUT": "ok 1 - a\\n  not ok 2 - b\\nok 3 - c\\n", "T2_RC": "1"}


def cases():
    yield case("all pass, text")
    yield case("all pass, tap", args=["--format", "tap"])
    yield case("all pass, json", args=["--format", "json"])
    yield case("an unknown format is text", args=["--format", "yaml"])
    yield case("verbose", args=["-v"])
    yield case("verbose, long form, tier 3 only", args=["--verbose", "--tier", "3"])
    yield case("tier 2 only, json", args=["--tier", "2", "--format", "json"])
    yield case("tier all spelled out", args=["--tier", "all", "--format", "tap"])
    yield case("a failing tier, text", env=FAIL2)
    yield case("a failing tier, tap", args=["--format", "tap"], env=FAIL2)
    yield case("a failing tier, json", args=["--format", "json"], env=FAIL2)
    yield case(
        "not ok lines with exit 0 still fail", env={"T1_OUT": "ok 1\\nnot ok 2 - x\\n"}
    )
    yield case(
        "a non-zero exit with no lines fails", env={"T4_OUT": "boom\\n", "T4_RC": "3"}
    )
    yield case(
        "exit 0 and no ok lines: the expected count",
        env={"T1_OUT": "all good\\n", "T3_OUT": ""},
    )
    yield case(
        "what counts as ok",
        args=["-v"],
        env={
            "T1_OUT": "ok 1\\n\\tok 2\\n   ok 3\\nok\\nokay 4\\n# ok 5\\n\\vok 6\\r\\nnot ok\\n"
        },
    )
    yield case(
        "stderr is captured with stdout, in order",
        args=["-v"],
        env={"T1_OUT": "ok 1 - out\\n", "T_STDERR": "warning on stderr\\n"},
    )
    yield case(
        "trailing newlines are dropped", args=["-v"], env={"T2_OUT": "ok 1\\n\\n\\n\\n"}
    )
    yield case("a tier printing only -n", env={"T3_OUT": "-n", "T3_RC": "1"})
    yield case("a tier printing only -e", env={"T3_OUT": "-e", "T3_RC": "1"})
    yield case("a tier killed by a signal", env={"T2_RC": "kill"})
    yield case(
        "every tier fails",
        args=["--format", "tap"],
        env={"T1_RC": "1", "T2_RC": "2", "T3_RC": "3", "T4_RC": "4"},
    )
    yield case("a missing tier script", setup=workspace(tiers=TIERS[:2] + TIERS[3:]))
    yield case(
        "a missing tier script, json",
        args=["--format", "json"],
        setup=workspace(tiers=TIERS[1:]),
    )
    yield case("help", args=["-h"])
    yield case("help, long form, after other options", args=["--tier", "1", "--help"])
    yield case("an unknown option", args=["--nope"])
    yield case("an unknown option after a good one", args=["-v", "x"])
    yield case("--tier without a value", args=["--tier"])
    yield case("--format without a value", args=["--tier", "1", "--format"])
    yield case("an empty tier value", args=["--tier", ""], skip=not EMPTY_ARRAY_OK)
    yield case("go.work marks the workspace", setup=workspace(marker="go.work"))

    def nested(root):
        write(root + "/tools/go.work", "")

    yield case("the nearest marker wins", setup=workspace(extra=nested))
    yield case(
        "BUILD_WORKSPACE_DIRECTORY wins",
        env={"BUILD_WORKSPACE_DIRECTORY": "{root}/tools"},
    )
    yield case(
        "an empty BUILD_WORKSPACE_DIRECTORY is ignored",
        env={"BUILD_WORKSPACE_DIRECTORY": ""},
    )
    yield case(
        "a BUILD_WORKSPACE_DIRECTORY that does not exist",
        env={"BUILD_WORKSPACE_DIRECTORY": "{root}/gone"},
    )
    yield case("no tier selected", args=["--tier", "5"], skip=not EMPTY_ARRAY_OK)
    yield case(
        "no tier selected, json",
        args=["--tier", "5", "--format", "json"],
        skip=not EMPTY_ARRAY_OK,
    )


def link_setup(root):
    workspace()(root)
    os.makedirs(root + "/bin2")
    os.symlink("../tools/platform-e2e/runner", root + "/bin2/runner")


def main():
    h = RunnerHarness("platform-e2e runner parity", SH, RS, base_path=BASE_PATH)
    for c in cases():
        if c.name in SKIPPED:
            print(
                "  skip  %s  (bash %s.%s stops on an empty array under set -u)"
                % (c.name, _BV[0], _BV[1])
            )
            continue
        h.check_via(c)
    # Run through a symlink: the workspace is found through the link, the
    # tier scripts are looked for beside the link (and are not there).
    h.check_via(case("run through a symlink", setup=link_setup), via="bin2/runner")
    return h.finish()


if __name__ == "__main__":
    sys.exit(main())
