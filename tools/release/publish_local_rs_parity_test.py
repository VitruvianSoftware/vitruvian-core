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
"""publish-local, the Rust port, against publish-local.sh: same exit code,
stdout, stderr, and the same calls -- git (clone, rev-parse, ls-remote, tag,
push), gh, npm (argv, working directory, and the npm token in the
environment), and the secret-store tool -- on every case below.

    bazel test //tools/release:publish_local_rs_parity_test

The script reads its JSON with `jq -r`; the port parses it natively. The
script side gets the host's jq when there is one (/usr/bin, /bin), else a
small stand-in for the four filters it uses (the RBE image has no jq). jq
1.7's "Could not open file X" and other versions' "Could not open X" are the
same message here.
"""

import json
import os
import shutil
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

GH = r"""#!/usr/bin/env bash
printf 'gh %s\n' "$*" >>"$LOGDIR/calls.log"
[ "${FAKE_GH_FAIL:-0}" = 1 ] && { echo "not logged in" >&2; exit 1; }
printf 'gho_TOKEN\n\n'
"""

GIT = r"""#!/usr/bin/env bash
printf 'git %s\n' "$*" >>"$LOGDIR/calls.log"
[ "$1" = -C ] && shift 2
case "$1" in
  clone)
    [ "${FAKE_CLONE_FAIL:-0}" = 1 ] && { echo "fatal: repository not found" >&2; exit 128; }
    for a; do last="$a"; done
    mkdir -p "$last/.git"; echo cloned ;;
  rev-parse)
    [ "${FAKE_REVPARSE_FAIL:-0}" = 1 ] && { echo "fatal: bad HEAD" >&2; exit 128; }
    echo "0123456789abcdef0123456789abcdef01234567" ;;
  ls-remote)
    # One write before any failure: a second one could die of SIGPIPE once
    # `grep -q .` has seen a line (the script's race, not compared here).
    [ "${FAKE_LSREMOTE_FAIL:-0}" = 1 ] && { echo "deadbeef	$4"; echo "fatal: unreachable" >&2; exit 2; }
    for t in ${FAKE_TAGGED:-}; do
      [ "$4" = "refs/tags/$t" ] && printf 'abc\trefs/tags/%s\n' "$t"
    done
    exit 0 ;;
  tag) echo "tagged $2" ;;
  push)
    echo "pushing $3" >&2
    [ "${FAKE_PUSH_FAIL:-0}" = 1 ] && exit 7
    exit 0 ;;
esac
"""

NPM = r"""#!/usr/bin/env bash
printf 'npm %s | pwd=%s PWD=%s token=%s\n' "$*" "$(pwd -P)" "$PWD" "${NODE_AUTH_TOKEN-<unset>}" >>"$LOGDIR/calls.log"
case "$1" in
  view)
    for p in ${FAKE_PUBLISHED:-}; do [ "$2" = "$p" ] && { echo "${2##*@}"; exit 0; }; done
    echo "npm ERR! 404" >&2; exit 1 ;;
esac
for p in ${FAKE_NPM_FAIL_ON:-}; do [ "$1" = "$p" ] && { echo "npm ERR! $1 failed" >&2; exit 3; }; done
echo "npm $1 ok"
"""

STORE = r"""#!/usr/bin/env bash
printf 'store %s | BWD=%s\n' "$*" "$BUILD_WORKSPACE_DIRECTORY" >>"$LOGDIR/calls.log"
echo "store: prompting (stdout)"
echo "store: note (stderr)" >&2
[ "${FAKE_STORE_FAIL:-0}" = 1 ] && exit 4
if [ "${FAKE_STORE_NOWRITE:-0}" != 1 ]; then
  mkdir -p "$BUILD_WORKSPACE_DIRECTORY/tools/sync-env-secrets/secrets/shared"
  printf 'npm_FRESH\n' >"$BUILD_WORKSPACE_DIRECTORY/tools/sync-env-secrets/secrets/shared/$3"
fi
"""

# The four filters publish-local.sh runs, for a host without jq.
JQ_SHIM = r"""#!{python} -IB
import json, sys
filt, path = sys.argv[2], sys.argv[3]
def pairs(p):
    d = {{}}
    for k, v in p:
        d[k] = v
    return d
try:
    text = open(path).read()
except OSError as e:
    sys.stderr.write("jq: error: Could not open %s: %s\n" % (path, e.strerror))
    sys.exit(2)
if not text.strip():
    sys.exit(0)
v = json.loads(text, object_pairs_hook=pairs)
def raw(x):
    return x if isinstance(x, str) else json.dumps(x, indent=2)
if filt == "to_entries[0].value":
    if isinstance(v, dict):
        r = next(iter(v.values()), None)
    elif isinstance(v, list):
        r = v[0] if v else None
    else:
        sys.exit(5)
elif filt.endswith(" // false"):
    k = filt[1:-9]
    r = v.get(k) if isinstance(v, dict) else None
    r = r if r not in (None, False) else False
else:
    k = filt[1:]
    if isinstance(v, list):
        sys.stderr.write('jq: error (at %s:%d): Cannot index array with string "%s"\n' % (path, text.count("\n"), k))
        sys.exit(5)
    r = v.get(k) if isinstance(v, dict) else None
print(raw(r) if not isinstance(r, bool) else ("true" if r else "false"))
"""

HOST_JQ = not os.environ.get("PUBLISH_LOCAL_PARITY_JQ_SHIM") and any(
    os.path.exists(os.path.join(d, "jq")) for d in ("/usr/bin", "/bin")
)


def repo(
    go=(),
    ts=(),
    slack=None,
    store=(),
    hidden=True,
):
    """A setup() writing the fakes and a repo at <root>/repo: go = [(name,
    manifest text or None)], ts = [(name, package.json dict or None)],
    store = [(dir, token)]."""

    def setup(root):
        b = os.path.join(root, "bin")
        write_exec(os.path.join(b, "gh"), GH)
        write_exec(os.path.join(b, "git"), GIT)
        write_exec(os.path.join(b, "npm"), NPM)
        if not HOST_JQ:
            write_exec(os.path.join(b, "jq"), JQ_SHIM.format(python=sys.executable))
        r = os.path.join(root, "repo")
        write_exec(os.path.join(r, "tools/sync-env-secrets/sync-env-secrets.sh"), STORE)
        os.makedirs(os.path.join(r, "packages/pulumi/library/go/pkg"), exist_ok=True)
        os.makedirs(
            os.path.join(r, "packages/pulumi/library/ts/packages"), exist_ok=True
        )
        for name, manifest in go:
            d = os.path.join(r, "packages/pulumi/library/go/pkg", name)
            os.makedirs(d, exist_ok=True)
            if manifest is not None:
                write(os.path.join(d, ".release-please-manifest.json"), manifest)
        for name, pj in ts:
            d = os.path.join(r, "packages/pulumi/library/ts/packages", name)
            os.makedirs(d, exist_ok=True)
            if pj is not None:
                write(
                    os.path.join(d, "package.json"),
                    pj if isinstance(pj, str) else json.dumps(pj),
                )
        if hidden:
            d = os.path.join(r, "packages/pulumi/library/go/pkg/.hidden")
            os.makedirs(d, exist_ok=True)
            write(os.path.join(d, ".release-please-manifest.json"), '{"x":"9.9.9"}')
        if slack is not None:
            write(
                os.path.join(r, "apps/mcp/slack/package.json"),
                slack if isinstance(slack, str) else json.dumps(slack),
            )
        for d, tok in store:
            write(
                os.path.join(
                    r, "tools/sync-env-secrets/secrets", d, "NPM_PUBLISH_TOKEN"
                ),
                tok,
            )

    return setup


GO = [
    ("cloud_run", '{"packages/pulumi/library/go/pkg/cloud_run": "0.3.0"}\n'),
    ("bucket", '{"go/pkg/bucket": "1.2.0", "other": "9.9.9"}'),
    ("nomanifest", None),
    ("zeta", '{"a": "2.0.0"}'),
]
TS = [
    ("alpha", {"name": "@v/alpha", "version": "1.0.0"}),
    ("beta", {"name": "@v/beta", "version": "2.0.0", "private": True}),
    ("gamma", {"name": "@v/gamma", "version": "3.0.0", "private": False}),
    ("nopkg", None),
]
SLACK = {"name": "@vitruviansoftware/mcp-slack", "version": "0.9.1"}


def env(**kw):
    e = {"BUILD_WORKSPACE_DIRECTORY": "{root}/repo", "LOGDIR": "{root}"}
    e.update(kw)
    return e


def main():
    h = Harness(
        "publish-local", need_env("PUBLISH_LOCAL_SH"), need_env("PUBLISH_LOCAL_RS")
    )
    full = repo(go=GO, ts=TS, store=[("shared", "npm_STORED\n")])
    jq_norm = [(rb"Could not open file ", b"Could not open ")]
    cases = [
        Case(
            "not via bazel run",
            ["pulumi-library"],
            env={"LOGDIR": "{root}"},
            setup=full,
        ),
        Case(
            "empty workspace dir",
            ["pulumi-library"],
            env=env(BUILD_WORKSPACE_DIRECTORY=""),
            setup=full,
        ),
        Case(
            "lib-only guard",
            ["pulumi-library", "--execute"],
            env=env(PUBLISH_LOCAL_LIB_ONLY="1"),
            setup=full,
        ),
        Case(
            "lib-only needs exactly 1",
            ["pulumi-library"],
            env=env(PUBLISH_LOCAL_LIB_ONLY="yes"),
            setup=full,
        ),
        Case("no arguments", [], env=env(), setup=full),
        Case("-h as the component", ["-h"], env=env(), setup=full),
        Case("-h after the component", ["pulumi-library", "-h"], env=env(), setup=full),
        Case("--help", ["mcp-slack", "--execute", "--help"], env=env(), setup=full),
        Case(
            "--package without a value",
            ["pulumi-library", "--package"],
            env=env(),
            setup=full,
        ),
        Case("unknown argument", ["pulumi-library", "--force"], env=env(), setup=full),
        Case("unknown component", ["devx"], env=env(), setup=full),
        Case(
            "pulumi-library dry run",
            ["pulumi-library"],
            env=env(
                FAKE_TAGGED="go/pkg/bucket/v1.2.0", FAKE_PUBLISHED="@v/gamma@3.0.0"
            ),
            setup=full,
        ),
        Case(
            "dry run, one Go package",
            ["pulumi-library", "--package", "zeta"],
            env=env(),
            setup=full,
        ),
        Case(
            "dry run, one npm package",
            ["pulumi-library", "--package", "alpha"],
            env=env(),
            setup=full,
        ),
        Case(
            "dry run, no such package",
            ["pulumi-library", "--package", "nope"],
            env=env(),
            setup=full,
        ),
        Case(
            "dry run, empty --package",
            ["pulumi-library", "--package", ""],
            env=env(),
            setup=full,
        ),
        Case(
            "dry run, empty repo",
            ["pulumi-library"],
            env=env(),
            setup=repo(hidden=False),
        ),
        Case(
            "execute, token in the store",
            ["pulumi-library", "--execute"],
            env=env(FAKE_TAGGED="go/pkg/cloud_run/v0.3.0"),
            setup=repo(
                go=GO,
                ts=TS,
                store=[
                    ("aaa/NPM_PUBLISH_TOKEN", "x"),
                    ("personal", "npm_P\n\n"),
                    ("shared", "npm_S"),
                ],
            ),
        ),
        Case(
            "execute, token stored now",
            ["pulumi-library", "--execute", "--package", "alpha"],
            env=env(),
            setup=repo(go=GO, ts=TS),
        ),
        Case(
            "execute, store tool fails",
            ["pulumi-library", "--execute"],
            env=env(FAKE_STORE_FAIL="1"),
            setup=repo(go=GO, ts=TS),
        ),
        Case(
            "execute, store tool writes nothing",
            ["mcp-slack", "--execute"],
            env=env(FAKE_STORE_NOWRITE="1"),
            setup=repo(slack=SLACK),
        ),
        Case(
            "gh not logged in",
            ["pulumi-library"],
            env=env(FAKE_GH_FAIL="1"),
            setup=full,
        ),
        Case(
            "clone fails", ["pulumi-library"], env=env(FAKE_CLONE_FAIL="1"), setup=full
        ),
        Case(
            "rev-parse fails",
            ["pulumi-library"],
            env=env(FAKE_REVPARSE_FAIL="1"),
            setup=full,
        ),
        Case(
            "ls-remote fails after output",
            ["pulumi-library"],
            env=env(FAKE_LSREMOTE_FAIL="1"),
            setup=full,
        ),
        Case(
            "push fails",
            ["pulumi-library", "--execute"],
            env=env(FAKE_PUSH_FAIL="1"),
            setup=full,
        ),
        Case(
            "npm install fails",
            ["pulumi-library", "--execute", "--package", "gamma"],
            env=env(FAKE_NPM_FAIL_ON="install"),
            setup=full,
        ),
        Case(
            "npm publish fails",
            ["mcp-slack", "--execute"],
            env=env(FAKE_NPM_FAIL_ON="publish"),
            setup=repo(slack=SLACK, store=[("shared", "t")]),
        ),
        Case("mcp-slack dry run", ["mcp-slack"], env=env(), setup=repo(slack=SLACK)),
        Case(
            "mcp-slack already published",
            ["mcp-slack", "--execute"],
            env=env(FAKE_PUBLISHED="@vitruviansoftware/mcp-slack@0.9.1"),
            setup=repo(slack=SLACK, store=[("shared", "t")]),
        ),
        Case(
            "mcp-slack execute",
            ["mcp-slack", "--execute"],
            env=env(),
            setup=repo(slack=SLACK, store=[("shared", "t")]),
        ),
        Case(
            "mcp-slack private",
            ["mcp-slack"],
            env=env(),
            setup=repo(slack={"name": "s", "version": "1", "private": True}),
        ),
        Case(
            "mcp-slack private is not boolean",
            ["mcp-slack"],
            env=env(),
            setup=repo(slack={"name": "s", "version": "1", "private": "yes"}),
        ),
        Case(
            "mcp-slack missing fields", ["mcp-slack"], env=env(), setup=repo(slack={})
        ),
        Case(
            "mcp-slack not checked out",
            ["mcp-slack"],
            env=env(),
            setup=repo(),
            normalise=jq_norm,
        ),
        Case(
            "mcp-slack package.json is an array",
            ["mcp-slack"],
            env=env(),
            setup=repo(slack="[1]\n"),
        ),
        Case(
            "manifest edge cases",
            ["pulumi-library"],
            env=env(),
            setup=repo(
                go=[
                    ("empty", "{}"),
                    ("dup", '{"a": "1.0.0", "b": "x", "a": "1.1.0"}'),
                    ("blank", "  \n"),
                ]
            ),
        ),
        Case(
            "npm missing",
            ["mcp-slack", "--execute"],
            env=env(PATH="{root}/bin:" + path_without("npm")),
            setup=lambda root: (
                repo(slack=SLACK, store=[("shared", "t")])(root),
                os.remove(os.path.join(root, "bin/npm")),
            ),
        ),
        Case(
            "git missing",
            ["pulumi-library"],
            env=env(PATH="{root}/bin:" + path_without("git")),
            setup=lambda root: (full(root), os.remove(os.path.join(root, "bin/git"))),
        ),
    ]
    for c in cases:
        h.check(c)
    return h.finish()


if __name__ == "__main__":
    sys.exit(main())
