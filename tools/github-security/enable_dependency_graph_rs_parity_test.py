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
"""enable-dependency-graph, the Rust port, against
enable-dependency-graph.sh: same exit code, stdout, stderr, and the same
calls to a fake `gh` and `sleep`, on every case below.

    bazel test //tools/github-security:enable_dependency_graph_rs_parity_test
"""

import os
import sys

sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shell-compat")
)
from parity_harness import Case, Harness, need_env, path_without, write_exec  # noqa: E402

GH = r"""#!/usr/bin/env bash
printf '%s\n' "$*" >>"$LOGDIR/gh.log"
case "$*" in
  *dependency-graph/sbom*)
    [ "${FAKE_ENABLED:-0}" = 1 ] && exit 0
    grep -q '/attach' "$LOGDIR/gh.log" || exit 1
    n=$(grep -c 'dependency-graph/sbom' "$LOGDIR/gh.log")
    [ "$n" -gt "${FAKE_ONLINE_AFTER:-1}" ] && exit 0
    echo "HTTP 404" >&2; exit 1 ;;
  *"-i user"*)
    [ "${FAKE_USER_FAIL:-0}" = 1 ] && { echo "HTTP 401" >&2; exit 4; }
    printf 'HTTP/2.0 200 OK\r\n'
    [ -n "${FAKE_SCOPES+x}" ] && printf '%s: %s\r\n' "${FAKE_SCOPES_HEADER:-X-Oauth-Scopes}" "$FAKE_SCOPES"
    printf 'Content-Type: application/json\r\n\r\n{"login":"x"}\n' ;;
  *--jq\ .visibility*)
    [ -n "${FAKE_VIS_OUT+x}" ] && printf '%s' "$FAKE_VIS_OUT"
    exit "${FAKE_VIS_RC:-0}" ;;
  "auth refresh"*) [ "${FAKE_REFRESH_FAIL:-0}" = 1 ] && exit 1; echo "refreshed" ;;
  *"-X POST"*"/attach"*) [ "${FAKE_ATTACH_FAIL:-0}" = 1 ] && { echo "HTTP 422" >&2; exit 1; }; echo '{"ok":true}' ;;
  *"-X POST"*) [ "${FAKE_CREATE_FAIL:-0}" = 1 ] && { echo "HTTP 422: GHAS" >&2; exit 1; }; echo 99 ;;
  *code-security/configurations*) printf '%s' "${FAKE_CONFIGS:-}" ;;
  *"--jq .id"*) [ "${FAKE_REPOID_FAIL:-0}" = 1 ] && { echo "HTTP 500" >&2; exit 5; }; echo 4242 ;;
  *) echo "fake gh: unexpected $*" >&2; exit 99 ;;
esac
"""

SLEEP = r"""#!/usr/bin/env bash
printf 'sleep %s\n' "$*" >>"$LOGDIR/gh.log"
[ "${FAKE_SLEEP_FAIL:-0}" = 1 ] && exit 130
exit 0
"""


def setup(root):
    os.makedirs(root + "/log")
    write_exec(root + "/bin/gh", GH)
    write_exec(root + "/bin/sleep", SLEEP)


def no_gh(root):
    os.makedirs(root + "/log")


ADMIN = {"FAKE_SCOPES": "gist, admin:org, repo", "FAKE_VIS_OUT": "public\n"}


def case(name, env=None, s=setup, **kw):
    e = {"LOGDIR": "{root}/log"}
    e.update(env or {})
    return Case(name=name, env=e, setup=s, **kw)


def cases():
    yield case("already enabled", {"FAKE_ENABLED": "1"})
    yield case("no gh", {"PATH": "{root}/bin:" + path_without("gh")}, s=no_gh)
    yield case("creates, attaches, comes online", ADMIN)
    yield case("comes online after a few polls", dict(ADMIN, FAKE_ONLINE_AFTER="4"))
    yield case("never comes online", dict(ADMIN, FAKE_ONLINE_AFTER="99"))
    yield case(
        "an interrupted sleep ends the run",
        dict(ADMIN, FAKE_ONLINE_AFTER="99", FAKE_SLEEP_FAIL="1"),
    )
    yield case("reuses an existing configuration", dict(ADMIN, FAKE_CONFIGS="77\n88\n"))
    yield case("an empty first line means none", dict(ADMIN, FAKE_CONFIGS="\n77\n"))
    yield case("create fails", dict(ADMIN, FAKE_CREATE_FAIL="1"))
    yield case("repo id lookup fails", dict(ADMIN, FAKE_REPOID_FAIL="1"))
    yield case("attach fails", dict(ADMIN, FAKE_ATTACH_FAIL="1"))
    yield case("private repo, no terminal", dict(ADMIN, FAKE_VIS_OUT="private\n"))
    yield case("visibility lookup fails", dict(ADMIN, FAKE_VIS_OUT="", FAKE_VIS_RC="1"))
    yield case(
        "visibility lookup fails after output",
        dict(ADMIN, FAKE_VIS_OUT="internal\n", FAKE_VIS_RC="2"),
    )
    yield case("visibility without newline", dict(ADMIN, FAKE_VIS_OUT="public"))
    yield case(
        "no admin:org, no terminal",
        {"FAKE_SCOPES": "gist, read:org, repo", "FAKE_VIS_OUT": "public\n"},
    )
    yield case("no scopes header", {"FAKE_VIS_OUT": "public\n"})
    yield case("empty scopes header", {"FAKE_SCOPES": "", "FAKE_VIS_OUT": "public\n"})
    yield case(
        "lower-case header, no spaces",
        {
            "FAKE_SCOPES": "repo,admin:org",
            "FAKE_SCOPES_HEADER": "x-oauth-scopes",
            "FAKE_VIS_OUT": "public\n",
        },
    )
    yield case(
        "admin:org look-alike",
        {"FAKE_SCOPES": "admin:orgs, read:org", "FAKE_VIS_OUT": "public\n"},
    )
    yield case("user lookup fails", {"FAKE_USER_FAIL": "1", "FAKE_VIS_OUT": "public\n"})
    yield case(
        "arguments are ignored", dict(ADMIN, FAKE_ENABLED="1"), args=["--force", "x"]
    )


def main():
    h = Harness(
        "enable-dependency-graph parity",
        need_env("ENABLE_DEPENDENCY_GRAPH_SH"),
        need_env("ENABLE_DEPENDENCY_GRAPH_RS"),
    )
    for c in cases():
        h.check(c)
    return h.finish()


if __name__ == "__main__":
    sys.exit(main())
