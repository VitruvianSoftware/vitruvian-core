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
"""techdocs:check, the Rust port, against check.sh: same exit code, stdout,
stderr, the same git and uv calls (argv and working directory), and the same
files left behind (every generated site/ removed) on every case below, under
each bash on the machine (macOS's /bin/bash 3.2 and a GNU bash 5 when one is
installed).

    bazel test //tools/techdocs:check_rs_parity_test

git and uv are fakes. git lists what the case says ($FAKE_TRACKED,
$FAKE_OTHERS); uv builds a site/ and prints and exits as the uv.out, uv.err
and uv.rc files beside each mkdocs.yml say.
"""

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

GIT = r"""#!/bin/sh
printf '%s\n' "$*" >>"$LOGDIR/git.log"
case "$*" in
  *--others*) printf '%s' "${FAKE_OTHERS:-}"; exit "${FAKE_OTHERS_RC:-0}" ;;
  *) printf '%s' "${FAKE_TRACKED:-}"; echo "git noise" >&2; exit "${FAKE_TRACKED_RC:-0}" ;;
esac
"""

UV = r"""#!/bin/sh
printf '%s | %s\n' "$PWD" "$*" >>"$LOGDIR/uv.log"
mkdir -p site && echo built >site/index.html
[ -f uv.out ] && cat uv.out
[ -f uv.err ] && cat uv.err >&2
[ -f uv.rc ] && exit "$(cat uv.rc)"
exit 0
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


def site(rel, out=None, err=None, rc=None, cfg="site_name: x\n"):
    """A mkdocs.yml at <root>/<rel>/ and what uv does there."""

    def make(root):
        d = os.path.join(root, rel)
        write(os.path.join(d, "mkdocs.yml"), cfg)
        if out is not None:
            write(os.path.join(d, "uv.out"), out)
        if err is not None:
            write(os.path.join(d, "uv.err"), err)
        if rc is not None:
            write(os.path.join(d, "uv.rc"), str(rc))

    return make


def case(
    name, tracked="", others=None, sites=(), env=None, uv=True, git=True, extra=None
):
    def setup(root):
        os.makedirs(root + "/log")
        if git:
            write_exec(root + "/bin/git", GIT)
        if uv:
            write_exec(root + "/bin/uv", UV)
        for s in sites:
            s(root)
        if extra:
            extra(root)

    e = {"LOGDIR": "{root}/log", "FAKE_TRACKED": tracked}
    if others is not None:
        e["FAKE_OTHERS"] = others
    e.update(env or {})
    return Case(name=name, env=e, setup=setup)


ESCAPES = (
    "C:\\path\\new \\x41 \\0101 \\101 \\e[31mred\\e[0m tab\\tX back\\\\slash \\q end\\"
)


def cases():
    three = [site("docs/a"), site("b"), site(".")]
    yield case("all pass", "docs/a/mkdocs.yml\nb/mkdocs.yml\nmkdocs.yml\n", sites=three)
    yield case(
        "untracked sites are listed too, deduplicated and sorted",
        "b/mkdocs.yml\ndocs/a/mkdocs.yml\n",
        others="docs/a/mkdocs.yml\nmkdocs.yml\nAa/mkdocs.yml\n",
        sites=three + [site("Aa")],
    )
    yield case(
        "one fails, with escapes in its log",
        "a/mkdocs.yml\nb/mkdocs.yml\n",
        sites=[
            site("a"),
            site("b", out="line one\n" + ESCAPES + "\n\n\n", err="err line\n", rc=1),
        ],
    )
    yield case(
        "every site fails, output with and without newlines",
        "a/mkdocs.yml\nb/mkdocs.yml\nc/mkdocs.yml\n",
        sites=[
            site("a", out="no newline", rc=2),
            site("b", err="only stderr\n", rc=1),
            site("c", rc=7),
        ],
    )
    yield case(
        "\\c in a log stops the report",
        "a/mkdocs.yml\nb/mkdocs.yml\n",
        sites=[site("a", out="before\\cafter\n", rc=1), site("b", out="later\n", rc=1)],
    )
    yield case(
        "\\x with no digit warns",
        "a/mkdocs.yml\n",
        sites=[site("a", out="bad \\xZZ hex\n", rc=1)],
    )
    yield case(
        "octal and hex edge digits",
        "a/mkdocs.yml\n",
        sites=[site("a", out="\\08 \\1018 \\x414 \\x4 \\7777\n", rc=1)],
    )
    yield case("no mkdocs.yml", "")
    yield case("only blank lines listed", "\n\n")
    yield case("not a git repository", "", env={"FAKE_TRACKED_RC": "128"})
    yield case(
        "listing untracked files fails",
        "a/mkdocs.yml\n",
        sites=[site("a")],
        env={"FAKE_OTHERS_RC": "1"},
    )
    yield case(
        "git missing",
        git=False,
        env={"PATH": "{root}/bin:" + path_without("git")},
    )
    yield case(
        "sort missing",
        "a/mkdocs.yml\n",
        sites=[site("a")],
        env={"PATH": "{root}/bin:" + path_without("sort")},
    )
    yield case(
        "uv missing",
        "a/mkdocs.yml\nmkdocs.yml\n",
        sites=[site("a"), site(".")],
        uv=False,
        env={"PATH": "{root}/bin:" + path_without("uv")},
    )
    yield case(
        "a listed directory that does not exist",
        "gone/mkdocs.yml\na/mkdocs.yml\n",
        sites=[site("a")],
    )
    yield case(
        "a path with a space is split into words",
        "my docs/mkdocs.yml\n",
        sites=[site("my docs"), site("docs")],
    )
    yield case(
        "stale site/ dirs and files are removed",
        "a/mkdocs.yml\nb/mkdocs.yml\n",
        sites=[site("a"), site("b", rc=1)],
        extra=lambda root: (
            write(root + "/a/site/old/stale.html", "old"),
            write(root + "/b/site", "a file named site"),
        ),
    )
    yield case(
        "BUILD_WORKSPACE_DIRECTORY is the repo",
        "x/mkdocs.yml\n",
        sites=[site("repo/x")],
        env={"BUILD_WORKSPACE_DIRECTORY": "{root}/repo"},
    )
    yield case(
        "BUILD_WORKSPACE_DIRECTORY empty means here",
        "x/mkdocs.yml\n",
        sites=[site("x")],
        env={"BUILD_WORKSPACE_DIRECTORY": ""},
    )
    yield case(
        "BUILD_WORKSPACE_DIRECTORY missing",
        "x/mkdocs.yml\n",
        env={"BUILD_WORKSPACE_DIRECTORY": "{root}/nope"},
    )
    yield case(
        "BUILD_WORKSPACE_DIRECTORY is a file",
        "x/mkdocs.yml\n",
        env={"BUILD_WORKSPACE_DIRECTORY": "{root}/log/git.log"},
        extra=lambda root: write(root + "/log/git.log", ""),
    )


def main():
    sh = need_env("CHECK_SH")
    rs = need_env("CHECK_RS")
    found = bashes()
    if not found:
        print("no bash found", file=sys.stderr)
        return 2
    rc = 0
    for b in found:
        print("== under %s" % b)
        h = Harness("techdocs:check parity (%s)" % b, sh, rs)
        h.bash = b
        for c in cases():
            h.check(c)
        rc |= h.finish()
    return rc


if __name__ == "__main__":
    sys.exit(main())
