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
"""//tools/ci:actionlint, the Rust port, against actionlint.sh: same exit
code, stdout, stderr, and the same actionlint and pin-check calls (argv,
working directory, SHELLCHECK_OPTS) on every case below, under each bash on
the machine (macOS's /bin/bash 3.2 and a GNU bash 5 when one is installed).

    bazel test //tools/ci:actionlint_rs_parity_test

actionlint, shellcheck and the pin check are fakes, handed over in the
environment or found in a runfiles tree that carries the real runfiles.bash
(so the script's runfiles lookup runs for real).
"""

import os
import shutil
import subprocess
import sys

# tools/ci is gazelle-managed; the harness comes in through the BUILD deps
# (//tools/shell-compat:parity_harness), not a requirement.
# gazelle:ignore parity_harness
sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shell-compat")
)
from parity_harness import (  # noqa: E402
    Case,
    Harness,
    need_env,
    path_without,
    write,
    write_exec,
)

ACTIONLINT = r"""#!/bin/sh
printf '%s | %s | SHELLCHECK_OPTS=%s\n' "$PWD" "$*" "${SHELLCHECK_OPTS-<unset>}" >>"$LOGDIR/actionlint.log"
[ -n "${FAKE_AL_OUT:-}" ] && printf '%s\n' "$FAKE_AL_OUT"
[ -n "${FAKE_AL_ERR:-}" ] && printf '%s\n' "$FAKE_AL_ERR" >&2
exit "${FAKE_AL_RC:-0}"
"""

PIN = r"""printf '%s | %s\n' "$PWD" "$0" >>"$LOGDIR/pin.log"
[ "${FAKE_PIN_RC:-0}" = 0 ] || echo "::error::actions/setup-go@v5 is not pinned to a full commit SHA" >&2
exit "${FAKE_PIN_RC:-0}"
"""

GIT = r"""#!/bin/sh
printf '%s | %s\n' "$PWD" "$*" >>"$LOGDIR/git.log"
[ -n "${FAKE_TOPLEVEL:-}" ] && { echo "$FAKE_TOPLEVEL"; exit 0; }
echo "fatal: not a git repository" >&2
exit 128
"""

BASH_CANDIDATES = [
    "/bin/bash",
    "/usr/bin/bash",
    "/usr/local/bin/bash",
    "/opt/homebrew/bin/bash",
    "/run/current-system/sw/bin/bash",
]


def bashes():
    """Every distinct bash on the machine (by real path)."""
    seen, found = set(), []
    for b in BASH_CANDIDATES:
        if os.access(b, os.X_OK):
            r = os.path.realpath(b)
            if r not in seen:
                seen.add(r)
                found.append(b)
    return found


RUNFILES_BASH = ""


def tools_in(d):
    write_exec(d + "/multitool/tools/actionlint/actionlint", ACTIONLINT)
    write_exec(d + "/multitool/tools/shellcheck/shellcheck", "#!/bin/sh\n")
    write(d + "/_main/tools/ci/require-pinned-actions.sh", PIN)


def case(
    name,
    args=(),
    env=None,
    tools=True,
    runfiles=False,
    extra=None,
    git=True,
    bash5_only=False,
):
    def setup(root):
        os.makedirs(root + "/log")
        os.makedirs(root + "/repo/.github/workflows")
        os.makedirs(root + "/repo/sub")
        if git:
            write_exec(root + "/bin/git", GIT)
        if tools:
            tools_in(root + "/t")
        if runfiles:
            tools_in(root + "/rf")
            dst = root + "/rf/bazel_tools/tools/bash/runfiles/runfiles.bash"
            os.makedirs(os.path.dirname(dst))
            shutil.copyfile(RUNFILES_BASH, dst)
        if extra:
            extra(root)

    e = {"LOGDIR": "{root}/log", "BUILD_WORKSPACE_DIRECTORY": "{root}/repo"}
    if tools:
        e.update(
            {
                "ACTIONLINT": "{root}/t/multitool/tools/actionlint/actionlint",
                "SHELLCHECK": "{root}/t/multitool/tools/shellcheck/shellcheck",
                "PIN_CHECK": "{root}/t/_main/tools/ci/require-pinned-actions.sh",
            }
        )
    e.update(env or {})
    c = Case(name=name, args=list(args), env=e, setup=setup)
    c.bash5_only = bash5_only
    return c


def cases():
    yield case("clean")
    yield case(
        "findings",
        env={"FAKE_AL_OUT": "w.yaml:3:5: bad [expression]", "FAKE_AL_RC": "1"},
    )
    yield case("actionlint cannot run", env={"FAKE_AL_ERR": "panic", "FAKE_AL_RC": "3"})
    yield case("unpinned action", env={"FAKE_PIN_RC": "1"})
    yield case("findings and unpinned", env={"FAKE_AL_RC": "1", "FAKE_PIN_RC": "2"})
    yield case(
        "file arguments resolve against BUILD_WORKSPACE_DIRECTORY",
        args=["a.yaml", "/abs/b.yaml", "-verbose", "", "sub/c.yaml"],
    )
    yield case(
        "file arguments resolve against BUILD_WORKING_DIRECTORY",
        args=["a.yaml", "-format", "{{json .}}"],
        env={"BUILD_WORKING_DIRECTORY": "{root}/repo/sub"},
    )
    yield case(
        "SHELLCHECK_OPTS is kept", env={"SHELLCHECK_OPTS": "--severity=error -x"}
    )
    yield case("an empty SHELLCHECK_OPTS is the default", env={"SHELLCHECK_OPTS": ""})
    yield case("actionlint missing", env={"ACTIONLINT": "{root}/nope"})
    yield case("shellcheck is a directory", env={"SHELLCHECK": "{root}/t"})
    yield case("pin check missing", env={"PIN_CHECK": "{root}/nope.sh"})
    yield case("no tools, no runfiles", tools=False)
    yield case(
        "no tools, an empty runfiles tree",
        tools=False,
        env={"RUNFILES_DIR": "{root}/log"},
    )
    yield case(
        "tools from runfiles",
        tools=False,
        runfiles=True,
        env={"RUNFILES_DIR": "{root}/rf"},
    )
    yield case(
        "runfiles plus an override",
        tools=False,
        runfiles=True,
        env={
            "RUNFILES_DIR": "{root}/rf",
            "FAKE_PIN_RC": "1",
            "PIN_CHECK": "{root}/rf/_main/tools/ci/require-pinned-actions.sh",
        },
    )
    yield case("-h", args=["-h"], tools=False)
    yield case("--help", args=["--help", "x"])
    yield case("help only as the first argument", args=["x", "--help"])
    # bash 3.2 reports a command it found but could not exec as status 1
    # (so "findings"); bash 4+ as 126/127 (so "could not run", exit 2). The
    # port follows bash 4+, which CI runs; the cases are checked there only.
    yield case(
        "actionlint not executable",
        extra=lambda root: os.chmod(
            root + "/t/multitool/tools/actionlint/actionlint", 0o644
        ),
        bash5_only=True,
    )
    yield case(
        "a relative actionlint runs from the repo",
        env={"ACTIONLINT": "t/multitool/tools/actionlint/actionlint"},
        bash5_only=True,
    )
    yield case(
        "bash missing for the pin check",
        env={"PATH": "{root}/bin:" + path_without("bash")},
    )
    yield case(
        "repo root from git",
        env={"BUILD_WORKSPACE_DIRECTORY": None, "FAKE_TOPLEVEL": "{root}/repo"},
        args=["w.yaml"],
    )
    yield case(
        "not in a repo: the current directory",
        env={"BUILD_WORKSPACE_DIRECTORY": None},
        args=["w.yaml"],
    )
    yield case(
        "git missing: the current directory",
        git=False,
        env={
            "BUILD_WORKSPACE_DIRECTORY": "",
            "PATH": "{root}/bin:" + path_without("git"),
        },
    )
    yield case(
        "BUILD_WORKSPACE_DIRECTORY missing",
        env={"BUILD_WORKSPACE_DIRECTORY": "{root}/gone"},
    )


def find_runfiles_bash():
    """bazel_tools' runfiles.bash, from this test's own runfiles."""
    rel = "bazel_tools/tools/bash/runfiles/runfiles.bash"
    for d in (os.environ.get("RUNFILES_DIR"), os.environ.get("TEST_SRCDIR")):
        if d and os.path.isfile(os.path.join(d, rel)):
            return os.path.join(d, rel)
    manifest = os.environ.get("RUNFILES_MANIFEST_FILE")
    if manifest and os.path.isfile(manifest):
        with open(manifest) as f:
            for line in f:
                k, _, v = line.rstrip("\n").partition(" ")
                if k == rel:
                    return v
    print("runfiles.bash is not in this test's runfiles", file=sys.stderr)
    sys.exit(2)


def main():
    global RUNFILES_BASH
    RUNFILES_BASH = find_runfiles_bash()
    sh = need_env("ACTIONLINT_SH")
    rs = need_env("ACTIONLINT_RS")
    found = bashes()
    if not found:
        print("no bash found", file=sys.stderr)
        return 2
    rc = 0
    for b in found:
        print("== under %s" % b)
        h = Harness("actionlint parity (%s)" % b, sh, rs)
        h.bash = b
        major = subprocess.run(
            [b, "-c", "echo ${BASH_VERSINFO[0]}"], capture_output=True, text=True
        ).stdout.strip()
        for c in cases():
            if c.bash5_only and major in ("2", "3"):
                print("  skip  %s  (bash %s exec-failure status)" % (c.name, major))
                continue
            h.check(c)
        rc |= h.finish()
    return rc


if __name__ == "__main__":
    sys.exit(main())
