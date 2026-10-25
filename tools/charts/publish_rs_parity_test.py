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
"""charts:publish, the Rust port, against publish.sh: same exit code, stdout,
stderr, the same git calls and the same helm calls (argv and working
directory) on every case below, under each bash on the machine (macOS's
/bin/bash 3.2 and a GNU bash 5 when one is installed).

    bazel test //tools/charts:publish_rs_parity_test

git and helm are fakes. Both tools write to the real /tmp/charts (the
script hard-codes it), so every chart here is named with a per-run token, the
fake `helm package` drops <name>-0.1.0.tgz there and the fake `helm push`
removes what it was handed.
"""

import glob
import os
import sys

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

TOKEN = "pt%dx" % os.getpid()

GIT = r"""#!/bin/sh
printf '%s | %s\n' "$PWD" "$*" >>"$LOGDIR/git.log"
case "$1 $2" in
  "rev-parse --show-toplevel")
    [ -n "${FAKE_TOPLEVEL:-}" ] && { echo "$FAKE_TOPLEVEL"; exit 0; }
    echo "fatal: not a git repository" >&2; exit 128 ;;
  "rev-parse --verify") exit "${FAKE_VERIFY_RC:-0}" ;;
  "diff --name-only")
    echo "diff noise" >&2
    printf '%s' "${FAKE_CHANGED:-}"
    exit "${FAKE_DIFF_RC:-0}" ;;
esac
exit 1
"""

HELM = r"""#!/bin/sh
printf '%s | %s\n' "$PWD" "$*" >>"$LOGDIR/helm.log"
case "$1" in
  package)
    for p in ${FAKE_PACKAGE_FAIL_ON:-}; do
      case "$2" in *"$p"*) echo "Error: chart broken" >&2; exit 3 ;; esac
    done
    n="$(sed -n 's/^name: //p' "$2/Chart.yaml" | head -1)"
    [ -n "$n" ] && : >"$4/$n-0.1.0.tgz"
    echo "Successfully packaged chart and saved it to: $4/$n-0.1.0.tgz" ;;
  push)
    shift
    for a in "$@"; do case "$a" in /tmp/charts/*) rm -f "$a" ;; esac; done
    for p in ${FAKE_PUSH_FAIL_ON:-}; do
      case "$*" in *"$p"*) echo "Error: unauthorized" >&2; exit 4 ;; esac
    done
    echo "Pushed: ghcr.io/x" ;;
esac
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


def clean_tmp():
    for f in glob.glob("/tmp/charts/%s*" % TOKEN) + glob.glob("/tmp/charts/-*.tgz"):
        os.remove(f)


def chart(rel, name=None, body=None):
    def make(root):
        if body is not None:
            text = body
        else:
            text = "apiVersion: v2\nname: %s%s\nversion: 0.1.0\n" % (TOKEN, name or "c")
        write(os.path.join(root, rel, "Chart.yaml"), text)

    return make


STD = [
    chart("apps/web/deploy/chart", "web"),
    chart("tools/x/deploy/chart", "x"),
    chart("deploy/chart", "top"),
    chart("bazel-out/k8/deploy/chart", "bazelout"),
    chart("svc/bazel-y/deploy/chart", "nested-bazel"),
    chart("a.b/deploy/chart", "dotted"),
    chart("apps/web/deploy/charts", "wrongdir"),
]


def case(name, charts=STD, env=None, git=True, helm=True, extra=None, cwd_sub=None):
    def setup(root):
        clean_tmp()
        os.makedirs(root + "/log")
        if git:
            write_exec(root + "/bin/git", GIT)
        if helm:
            write_exec(root + "/bin/helm", HELM)
        for c in charts:
            c(root)
        if extra:
            extra(root)

    e = {"LOGDIR": "{root}/log", "BUILD_WORKSPACE_DIRECTORY": "{root}"}
    e.update(env or {})
    return Case(
        name=name,
        env=e,
        setup=setup,
        normalise=[(TOKEN.encode(), b"<T>")],
    )


def cases():
    yield case(
        "workflow_dispatch publishes everything",
        env={"GITHUB_EVENT_NAME": "workflow_dispatch"},
    )
    yield case("no BEFORE_REV publishes everything")
    yield case(
        "forced push publishes everything",
        env={"FORCED_PUSH": "true", "BEFORE_REV": "abc"},
    )
    yield case(
        "FORCED_PUSH=false with a good base scopes",
        env={
            "FORCED_PUSH": "false",
            "BEFORE_REV": "abc",
            "FAKE_CHANGED": "tools/x/deploy/chart/values.yaml\n",
        },
    )
    yield case(
        "unresolvable base publishes everything",
        env={"BEFORE_REV": "0000", "FAKE_VERIFY_RC": "1"},
    )
    yield case(
        "only changed charts are published",
        env={
            "BEFORE_REV": "abc",
            "FAKE_CHANGED": "apps/web/deploy/chart/values.yaml\ndeploy/chart/Chart.yaml\nREADME.md\n",
        },
    )
    yield case(
        "the chart dir is a regex: a.b matches axb",
        env={"BEFORE_REV": "abc", "FAKE_CHANGED": "axb/deploy/chart/t.yaml"},
    )
    yield case(
        "a path must start with the dir",
        env={
            "BEFORE_REV": "abc",
            "FAKE_CHANGED": "x/apps/web/deploy/chart/a\napps/web/deploy/chartX/a\n",
        },
    )
    yield case("nothing changed", env={"BEFORE_REV": "abc", "FAKE_CHANGED": ""})
    yield case(
        "git diff fails: || true keeps what it printed",
        env={
            "BEFORE_REV": "abc",
            "FAKE_CHANGED": "svc/bazel-y/deploy/chart/x\n",
            "FAKE_DIFF_RC": "128",
        },
    )
    yield case(
        "git missing: base untrustworthy",
        git=False,
        env={"BEFORE_REV": "abc", "PATH": "{root}/bin:" + path_without("git")},
    )
    yield case("helm package fails", env={"FAKE_PACKAGE_FAIL_ON": "tools/x"})
    yield case("helm push fails", env={"FAKE_PUSH_FAIL_ON": "x-0.1.0"})
    yield case(
        "helm missing", helm=False, env={"PATH": "{root}/bin:" + path_without("helm")}
    )
    yield case(
        "Chart.yaml without a name pushes the literal glob",
        charts=[chart("n/deploy/chart", body="apiVersion: v2\nversion: 1\n")],
    )
    yield case(
        "name edge cases: extra colon, CRLF, indented first",
        charts=[
            chart("p/deploy/chart", body=" name: no\nname: %sp: extra\n" % TOKEN),
            chart("q/deploy/chart", body="name: %sq\r\n" % TOKEN),
            chart("r/deploy/chart", body="name:%sr\n" % TOKEN),
        ],
    )
    yield case(
        "older packages in /tmp/charts are pushed too, sorted",
        charts=[chart("m/deploy/chart", "multi")],
        extra=lambda root: [
            open("/tmp/charts/%smulti-%s.tgz" % (TOKEN, v), "w").close()
            for v in ("0.0.9", "0.0.10")
        ],
    )
    yield case("no charts at all", charts=[])
    yield case(
        "symlinked directories are not followed",
        charts=[chart("real/deploy/chart", "real")],
        extra=lambda root: os.symlink(root + "/real", root + "/link"),
    )
    yield case(
        "repo root from git when not under bazel run",
        charts=[chart("repo/s/deploy/chart", "s"), chart("outside/deploy/chart", "o")],
        env={"BUILD_WORKSPACE_DIRECTORY": None, "FAKE_TOPLEVEL": "{root}/repo"},
    )
    yield case(
        "not in a git repo: the current directory",
        charts=[chart("s/deploy/chart", "s")],
        env={"BUILD_WORKSPACE_DIRECTORY": ""},
    )
    yield case(
        "BUILD_WORKSPACE_DIRECTORY missing",
        env={"BUILD_WORKSPACE_DIRECTORY": "{root}/nope"},
    )


def main():
    sh = need_env("PUBLISH_SH")
    rs = need_env("PUBLISH_RS")
    found = bashes()
    if not found:
        print("no bash found", file=sys.stderr)
        return 2
    rc = 0
    try:
        for b in found:
            print("== under %s" % b)
            h = Harness("charts:publish parity (%s)" % b, sh, rs)
            h.bash = b
            for c in cases():
                h.check(c)
            rc |= h.finish()
    finally:
        clean_tmp()
    return rc


if __name__ == "__main__":
    sys.exit(main())
