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
"""agent-app, the Rust port, against agent-app.sh: same exit code, stdout,
stderr, files, and the same calls to fake curl, gh, git, sleep and landed
gate, on every case below.

    bazel test //tools/agent-app:agent_app_rs_parity_test

The fakes log every call into the sandbox, so what each one DID is compared
too. curl logs the Authorization header it was handed on /dev/fd/63; a JWT
in it is decoded and checked here (algorithm, issuer, a 600s lifetime with
iat backdated, a 2048-bit signature that verifies), then written as a
summary, since the two runs need not fall in the same second. The script
needs jq for the answers it reads itself (the hermetic one, JQ_BIN); gh's
--jq filters run through it too, on responses saved from GitHub (testdata/).
"""

import base64
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shell-compat")
)
from parity_harness import Case, Harness, need_env, write, write_exec  # noqa: E402

SECRET = "ghs_SENTINEL_never_print_me"

CURL = r"""#!/usr/bin/env bash
{ set +x; } 2>/dev/null
log="$LOGDIR/calls.log"
args="" prev=""
for a in "$@"; do
  args="$args|$a"
  if [ "$prev" = -H ]; then case "$a" in @*) printf 'curl header: %s\n' "$(cat "${a#@}")" >>"$log" ;; esac; fi
  prev="$a"
done
printf 'curl%s\n' "$args" >>"$log"
n=$(($(cat "$LOGDIR/curl.count" 2>/dev/null || echo 0) + 1)); echo "$n" >"$LOGDIR/curl.count"
var="FAKE_CURL_OUT_$n"; eval "o=\${$var-\${FAKE_CURL_OUT-}}"
var="FAKE_CURL_EXIT_$n"; eval "x=\${$var-\${FAKE_CURL_EXIT-0}}"
[ "$x" = 0 ] || { echo "curl: (22) The requested URL returned error: 401" >&2; exit "$x"; }
printf '%s' "$o"
"""

GH = r"""#!/usr/bin/env bash
{ set +x; } 2>/dev/null
log="$LOGDIR/calls.log"
if [ "${GH_TOKEN:-}" = "$FAKE_SECRET" ]; then t=agent; else t="other(${GH_TOKEN:-unset})"; fi
[ -n "${GITHUB_TOKEN+x}" ] && [ -z "$GITHUB_TOKEN" ] && g=empty || g="${GITHUB_TOKEN-unset}"
(IFS='|'; printf 'gh[%s,%s,%s]|%s\n' "$t" "$g" "$PWD" "$*") >>"$log"
filter="" prev=""
for a in "$@"; do [ "$prev" = --jq ] && filter="$a"; prev="$a"; done
answer() { # kind list -> the saved response for this read, through the real filter
  local n file
  n=$(($(cat "$LOGDIR/$1.count" 2>/dev/null || echo 0) + 1))
  echo "$n" >"$LOGDIR/$1.count"
  file="$(printf '%s\n' "$2" | tr ';' '\n' | sed -n "${n}p")"
  [ -n "$file" ] || file="$(printf '%s\n' "$2" | tr ';' '\n' | tail -1)"
  "$FAKE_JQ" -r "$filter" "$FAKE_FIXTURES/$file.json"
}
case "$1 $2" in
  "pr view")
    case "$*" in
      *"--json state"*) [ -n "${FAKE_STATE_FAIL:-}" ] && { echo "fake: no" >&2; exit 1; }; echo "${FAKE_STATE-MERGED}" ;;
      *) [ -n "${FAKE_VIEW_FAIL:-}" ] && { echo "GraphQL: Could not resolve" >&2; exit 1; }
         [ -n "${FAKE_VIEW_EMPTY:-}" ] && exit 0
         "$FAKE_JQ" -r "$filter" "$FAKE_FIXTURES/pr-view-id.json" ;;
    esac ;;
  "pr list") [ -n "${FAKE_LIST_FAIL:-}" ] && { echo "HTTP 502" >&2; exit 1; }; printf '%s' "${FAKE_OPEN:-}" ;;
  "api graphql")
    case "$*" in
      *dequeuePullRequest*) exit "${FAKE_DEQUEUE_EXIT:-0}" ;;
      *"labels(first"*)
        n=$(($(cat "$LOGDIR/holdfail.count" 2>/dev/null || echo 0) + 1)); echo "$n" >"$LOGDIR/holdfail.count"
        [ "${FAKE_HOLD_FAIL_AT:-0}" = "$n" ] && { echo "HTTP 500" >&2; exit 1; }
        answer hold "${FAKE_HOLD:-hold-open}" ;;
      *mergeMethod*) [ -n "${FAKE_ENQ_FAIL:-}" ] && exit 1; answer enq "${FAKE_ENQ:-enqueue-armed}" ;;
      *) echo "fake gh: unexpected query" >&2; exit 1 ;;
    esac ;;
  "api -X") exit "${FAKE_DELETE_EXIT:-0}" ;;
  "pr merge") exit "${FAKE_MERGE_EXIT:-0}" ;;
  "pr edit") exit "${FAKE_EDIT_EXIT:-0}" ;;
  "pr comment") exit "${FAKE_COMMENT_EXIT:-0}" ;;
  *)
    case "$1" in
      api) printf '%s\n' "${FAKE_SHA_NOW-}"; exit "${FAKE_SHA_EXIT:-0}" ;;
    esac
    echo "gh ran: $*"; echo "gh stderr" >&2; exit "${FAKE_GH_EXIT:-0}" ;;
esac
"""

GIT = r"""#!/usr/bin/env bash
(IFS='|'; printf 'git[%s]|%s\n' "$PWD" "$*") >>"$LOGDIR/calls.log"
case "$*" in
  *--git-common-dir*) [ -n "${FAKE_GIT_COMMON:-}" ] || exit 128; echo "$FAKE_GIT_COMMON" ;;
  *"rev-parse --verify"*) [ -n "${FAKE_GIT_SHA:-}" ] || exit 1; echo "$FAKE_GIT_SHA" ;;
  *) echo "fatal: not a git repository" >&2; exit 128 ;;
esac
"""

SLEEP = r"""#!/usr/bin/env bash
printf 'sleep|%s\n' "$*" >>"$LOGDIR/calls.log"
exit "${FAKE_SLEEP_EXIT:-0}"
"""

LANDED = r"""#!/usr/bin/env bash
if [ "${GH_TOKEN:-}" = "$FAKE_SECRET" ]; then t=agent; else t=other; fi
printf 'landed[%s]|%s\n' "$t" "$*" >>"$LOGDIR/calls.log"
echo "gate says: ${FAKE_GATE_SAYS:-landed}"
echo "gate stderr" >&2
echo "second line"
exit "${FAKE_GATE_EXIT:-0}"
"""

SHA = "ed8e62380b5893f43aa4f6696991e116f1366e42"
OTHER_SHA = "0000000000000000000000000000000000000000"
QUEUE = "gh-readonly-queue/main/pr-1264-" + SHA

KEY = ""
JQ = ""
FIXTURES = ""
HERE = ""

AWK_RE = re.compile(rb"(?m)^awk: .*\n(?: source line number 1\n)?")
JWT_RE = re.compile(
    rb"Bearer ([A-Za-z0-9_=+/-]*)\.([A-Za-z0-9_=+/-]*)\.([A-Za-z0-9_=+/-]*)"
)


def b64d(s: bytes) -> bytes:
    s = s.replace(b"-", b"+").replace(b"_", b"/")
    return base64.b64decode(s + b"=" * (-len(s) % 4))


def jwt_summary(m) -> bytes:
    """A JWT, checked and summarised: it must be RS256, carry a 600s
    lifetime with iat backdated, use the base64url alphabet unpadded, and
    its signature must verify against the throwaway key."""
    h, p, sig = m.group(1), m.group(2), m.group(3)
    notes = []
    if re.search(rb"[+/=]", m.group(0)[7:]):
        notes.append(b"NOT-base64url")
    try:
        hdr = b64d(h)
        pay = json.loads(b64d(p))
    except Exception as e:  # noqa: BLE001
        return b"Bearer <JWT unreadable: %s>" % str(e).encode()
    now = int(time.time())
    life = pay.get("exp", 0) - pay.get("iat", 0)
    if not (now - 120 <= pay.get("iat", 0) <= now - 55):
        notes.append(b"iat-not-backdated")
    sigok = b"none"
    if sig:
        d = tempfile.mkdtemp(dir=os.environ.get("TEST_TMPDIR"))
        with open(d + "/in", "wb") as f:
            f.write(h + b"." + p)
        with open(d + "/sig", "wb") as f:
            f.write(b64d(sig))
        subprocess.run(
            ["openssl", "pkey", "-in", KEY, "-pubout", "-out", d + "/pub"],
            capture_output=True,
        )
        r = subprocess.run(
            [
                "openssl",
                "dgst",
                "-sha256",
                "-verify",
                d + "/pub",
                "-signature",
                d + "/sig",
                d + "/in",
            ],
            capture_output=True,
        )
        sigok = b"verifies" if r.returncode == 0 else b"BAD"
        shutil.rmtree(d, ignore_errors=True)
    return b"Bearer <JWT header=%s iss=%s life=%d sig=%s%s>" % (
        hdr,
        str(pay.get("iss")).encode(),
        life,
        sigok,
        (b" " + b",".join(notes)) if notes else b"",
    )


def setup(root, keys=("wren", "beacon", "scout", "forge"), extra=None):
    os.makedirs(root + "/log", exist_ok=True)
    write_exec(root + "/bin/curl", CURL)
    write_exec(root + "/bin/gh", GH)
    write_exec(root + "/bin/git", GIT)
    write_exec(root + "/bin/sleep", SLEEP)
    os.symlink(JQ, root + "/bin/jq")
    write_exec(root + "/landed.sh", LANDED)
    os.makedirs(root + "/keys", exist_ok=True)
    for k in keys:
        shutil.copy(KEY, root + "/keys/%s.pem" % k)
    os.makedirs(root + "/work", exist_ok=True)
    if extra:
        extra(root)


def no_keys(root):
    setup(root, keys=())


def base_env():
    return {
        "LOGDIR": "{root}/log",
        "FAKE_SECRET": SECRET,
        "FAKE_JQ": JQ,
        "FAKE_FIXTURES": FIXTURES,
        "AGENT_KEY_DIR": "{root}/keys",
        "BUILD_WORKING_DIRECTORY": "{root}/work",
        "FAKE_CURL_OUT": '{"token":"%s"}' % SECRET,
        "AGENT_APP_VERIFY_TRIES": "2",
        "AGENT_APP_VERIFY_SLEEP": "0",
        "GITHUB_TOKEN": "ambient",
        "GITHUB_API_URL": "https://api.example.test",
    }


def case(name, args, env=None, s=setup, **kw):
    e = base_env()
    e.update(env or {})
    kw.setdefault("normalise", []).append((JWT_RE, jwt_summary))
    # awk's complaint about a file it cannot open is worded by whichever awk
    # this machine has (BWK on macOS, mawk or gawk on Linux); that it
    # complains, and what happens next, is what is compared.
    kw["normalise"].append((AWK_RE, b"<awk cannot open a file>\n"))
    kw["ignore"] = kw.get("ignore", []) + [
        r"bin/",
        r"keys/",
        r"landed\.sh",
        r"log/.*\.count$",
    ]
    return Case(name=name, args=args, env=e, setup=s, **kw)


# Under bazel test: the overrides of the committed files count.
IN_TEST = {"TEST_TMPDIR": "{root}/tmp"}


def cases():
    # --- dispatch -----------------------------------------------------------
    yield case("no command: usage, exit 1", [])
    yield case("help", ["help"])
    yield case("-h", ["-h"])
    yield case("--help", ["--help"])
    yield case("unknown command", ["nonsense"])
    yield case("empty command", [""])

    # --- convert ------------------------------------------------------------
    conv = '{"id":4521094,"slug":"vitruvian-wren-agent","owner":{"login":"VitruvianSoftware"},"pem":"-----BEGIN RSA PRIVATE KEY-----\\nMIIE\\n-----END RSA PRIVATE KEY-----\\n"}'
    yield case("convert: no args", ["convert"])
    yield case("convert: one arg", ["convert", "code"])
    yield case(
        "convert: existing key",
        ["convert", "code", "{root}/work/existing.pem"],
        s=lambda r: setup(r, extra=lambda r: write(r + "/work/existing.pem", "x")),
    )
    yield case(
        "convert: writes the pem 600 and the summary",
        ["convert", "c0de", "{root}/work/new.pem"],
        {"FAKE_CURL_OUT": conv},
    )
    yield case(
        "convert: relative out", ["convert", "c0de", "new.pem"], {"FAKE_CURL_OUT": conv}
    )
    yield case(
        "convert: curl fails",
        ["convert", "c0de", "{root}/work/new.pem"],
        {"FAKE_CURL_EXIT": "22"},
    )
    yield case(
        "convert: no pem in the answer",
        ["convert", "c0de", "{root}/work/new.pem"],
        {"FAKE_CURL_OUT": '{"message":"Not Found"}'},
    )
    yield case(
        "convert: pem false",
        ["convert", "c0de", "{root}/work/new.pem"],
        {"FAKE_CURL_OUT": '{"pem":false}'},
    )
    yield case(
        "convert: answer is an array",
        ["convert", "c0de", "{root}/work/new.pem"],
        {"FAKE_CURL_OUT": "[1,2]"},
    )
    yield case(
        "convert: truncated answer",
        ["convert", "c0de", "{root}/work/new.pem"],
        {"FAKE_CURL_OUT": '{"pem":"x",'},
    )
    yield case(
        "convert: owner missing",
        ["convert", "c0de", "{root}/work/new.pem"],
        {"FAKE_CURL_OUT": '{"pem":"P","id":1}'},
    )
    yield case(
        "convert: owner is a string",
        ["convert", "c0de", "{root}/work/new.pem"],
        {"FAKE_CURL_OUT": '{"pem":"P","id":1,"owner":"o"}'},
    )
    yield case(
        "convert: out dir missing",
        ["convert", "c0de", "{root}/nodir/new.pem"],
        {"FAKE_CURL_OUT": conv},
    )
    yield case(
        "convert: empty answer",
        ["convert", "c0de", "{root}/work/new.pem"],
        {"FAKE_CURL_OUT": ""},
    )

    # --- installations, repos, token ----------------------------------------
    inst = '[{"id":152054411,"account":{"login":"VitruvianSoftware"},"repository_selection":"selected"},{"id":2,"account":null}]'
    yield case("installations: usage", ["installations", "1"])
    yield case(
        "installations: lists",
        ["installations", "4521094", "{root}/keys/wren.pem"],
        {"FAKE_CURL_OUT": inst},
    )
    yield case(
        "installations: empty",
        ["installations", "4521094", "{root}/keys/wren.pem"],
        {"FAKE_CURL_OUT": "[]"},
    )
    yield case(
        "installations: object of objects",
        ["installations", "9", "{root}/keys/wren.pem"],
        {"FAKE_CURL_OUT": '{"b":{"id":2},"a":{"id":1,"account":{"login":"x"}}}'},
    )
    yield case(
        "installations: a bad element",
        ["installations", "9", "{root}/keys/wren.pem"],
        {"FAKE_CURL_OUT": '[{"id":1},"oops",{"id":3}]'},
    )
    yield case(
        "installations: an object id",
        ["installations", "9", "{root}/keys/wren.pem"],
        {"FAKE_CURL_OUT": '[{"id":{"x":[1,"a"]},"repository_selection":true}]'},
    )
    yield case(
        "installations: curl fails",
        ["installations", "9", "{root}/keys/wren.pem"],
        {"FAKE_CURL_EXIT": "22"},
    )
    yield case(
        "installations: unreadable key still calls curl",
        ["installations", "9", "{root}/keys/none.pem"],
        {"FAKE_CURL_OUT": "[]"},
    )
    yield case(
        "installations: a bad key (openssl fails)",
        ["installations", "9", "{root}/work/bad.pem"],
        {"FAKE_CURL_OUT": "[]"},
        s=lambda r: setup(r, extra=lambda r: write(r + "/work/bad.pem", "not a key\n")),
        normalise=[
            (rb"(?m)^[0-9A-F]+:error:.*\n", b""),
            (rb"(?m)^(Could not|unable to|Error).*\n", b""),
        ],
    )
    yield case("repos: usage", ["repos", "1", "k"])
    yield case(
        "repos: lists",
        ["repos", "4521094", "{root}/keys/wren.pem", "152054411"],
        {
            "FAKE_CURL_OUT_2": '{"repositories":[{"full_name":"VitruvianSoftware/vitruvian-core"},{"full_name":"a/b"}]}'
        },
    )
    yield case(
        "repos: token fails",
        ["repos", "4521094", "{root}/keys/wren.pem", "152054411"],
        {"FAKE_CURL_EXIT_1": "22"},
    )
    yield case(
        "repos: list fails",
        ["repos", "4521094", "{root}/keys/wren.pem", "152054411"],
        {"FAKE_CURL_EXIT_2": "7"},
    )
    yield case(
        "repos: no repositories",
        ["repos", "4521094", "{root}/keys/wren.pem", "152054411"],
        {"FAKE_CURL_OUT_2": "{}"},
    )
    yield case("token: usage", ["token", "1", "k"])
    yield case(
        "token: mints", ["token", "4521094", "{root}/keys/wren.pem", "152054411"]
    )
    yield case(
        "token: extra args ignored",
        ["token", "4521094", "{root}/keys/wren.pem", "152054411", "x"],
    )
    yield case(
        "token: no token in the answer",
        ["token", "4521094", "{root}/keys/wren.pem", "1"],
        {"FAKE_CURL_OUT": '{"message":"Bad credentials"}'},
    )
    yield case(
        "token: empty answer",
        ["token", "4521094", "{root}/keys/wren.pem", "1"],
        {"FAKE_CURL_OUT": ""},
    )
    yield case(
        "token: curl fails",
        ["token", "4521094", "{root}/keys/wren.pem", "1"],
        {"FAKE_CURL_EXIT": "22"},
    )
    yield case(
        "token: a numeric token",
        ["token", "4521094", "{root}/keys/wren.pem", "1"],
        {"FAKE_CURL_OUT": '{"token":12}'},
    )
    yield case(
        "token: two answers",
        ["token", "4521094", "{root}/keys/wren.pem", "1"],
        {"FAKE_CURL_OUT": '{"token":"a"}\n{"token":null}\n'},
    )
    yield case(
        "token: garbage after",
        ["token", "4521094", "{root}/keys/wren.pem", "1"],
        {"FAKE_CURL_OUT": '{"token":"a"} nul'},
    )
    yield case(
        "token: unfinished string",
        ["token", "4521094", "{root}/keys/wren.pem", "1"],
        {"FAKE_CURL_OUT": '{"token":"a'},
    )
    yield case(
        "token: API URL with a path",
        ["token", "4521094", "{root}/keys/wren.pem", "1"],
        {"GITHUB_API_URL": "http://127.0.0.1:1/api/v3"},
    )
    yield case(
        "token: API URL empty uses github",
        ["token", "4521094", "{root}/keys/wren.pem", "1"],
        {"GITHUB_API_URL": ""},
    )

    # --- login / env ----------------------------------------------------------
    yield case("login: no agent", ["login"])
    yield case("login: unknown agent", ["login", "nosuchagent"])
    yield case("login: no key", ["login", "beacon"], {"AGENT_KEY_DIR": "/nonexistent"})
    yield case("login: mints beacon's token", ["login", "beacon"])
    yield case(
        "login: registry unreadable",
        ["login", "wren"],
        {"AGENT_REGISTRY": "{root}/none.tsv"},
    )
    yield case(
        "login: registry unreadable, no agent",
        ["login"],
        {"AGENT_REGISTRY": "{root}/none.tsv"},
    )
    yield case(
        "login: own registry",
        ["login", "x"],
        {"AGENT_REGISTRY": "{root}/reg.tsv"},
        s=lambda r: setup(
            r,
            keys=("x",),
            extra=lambda r: write(
                r + "/reg.tsv", "# c\nx\t11\t22\t33\nx\t12\nshort\t1\n\ny\t\t3\t4\n"
            ),
        ),
    )
    yield case(
        "login: an escape in the name",
        ["login", "a\\tb"],
        {"AGENT_REGISTRY": "{root}/reg.tsv"},
        s=lambda r: setup(r, extra=lambda r: write(r + "/reg.tsv", "a\tb\t1\t2\t3\n")),
    )
    yield case("env: no agent", ["env"])
    yield case("env: unknown agent", ["env", "nosuchagent"])
    yield case("env: no key", ["env", "beacon"], {"AGENT_KEY_DIR": "/nonexistent"})
    yield case("env: emits token and identity", ["env", "beacon"])
    yield case("env: token request fails", ["env", "wren"], {"FAKE_CURL_EXIT": "22"})
    yield case(
        "env: registry unreadable",
        ["env", "wren"],
        {"AGENT_REGISTRY": "{root}/none.tsv"},
    )

    # --- key folder resolution ---------------------------------------------
    def ws(r):
        setup(r)
        os.makedirs(r + "/ws/tools/sync-env-secrets", exist_ok=True)
        os.makedirs(r + "/main/tools/sync-env-secrets/agent-keys", exist_ok=True)
        shutil.copy(KEY, r + "/main/tools/sync-env-secrets/agent-keys/wren.pem")

    wsenv = {
        "AGENT_KEY_DIR": None,
        "BUILD_WORKSPACE_DIRECTORY": "{root}/ws",
        "AGENT_REGISTRY": HERE + "/agents.tsv",
    }
    yield case(
        "worktree: keys from the main checkout",
        ["login", "wren"],
        dict(wsenv, FAKE_GIT_COMMON="{root}/main/.git"),
        s=ws,
    )
    yield case("worktree: git finds nothing", ["login", "wren"], wsenv, s=ws)
    yield case(
        "worktree: main has no keys",
        ["login", "wren"],
        dict(wsenv, FAKE_GIT_COMMON="{root}/nowhere/.git"),
        s=ws,
    )
    yield case(
        "workspace: registry from the workspace",
        ["login", "wren"],
        {"BUILD_WORKSPACE_DIRECTORY": "{root}/ws"},
        s=ws,
    )
    yield case(
        "AGENT_KEY_DIR as given",
        ["login", "wren"],
        dict(wsenv, AGENT_KEY_DIR="/given", FAKE_GIT_COMMON="{root}/main/.git"),
        s=ws,
    )

    # --- pass-through commands ------------------------------------------------
    passthrough = [
        [
            "pr-edit",
            "12",
            "--title",
            "two words",
            "--add-label",
            "x",
            "--body-file",
            "pr.md",
        ],
        ["pr-comment", "12", "--body-file", "note.md"],
        ["pr-comment", "12", "--body", "looks good"],
        ["pr-review", "12", "--approve"],
        ["pr-review", "12", "--approve", "--body", "LGTM"],
        ["pr-review", "12", "-ab", "LGTM"],
        ["pr-review", "12", "--comment", "--body-file", "note.md"],
        ["pr-review", "12", "--request-changes", "-b", "needs a test"],
        ["pr-review", "12", "--body", "--approve", "--comment"],
        ["pr-review", "12", "--approve", "-R", "o/r"],
        ["pr-review", "12", "--approve=true", "--repo=o/r", "--body=x"],
        ["pr-ready", "12"],
        ["pr-close", "12", "--comment", "superseded by #13", "--delete-branch"],
        ["run-rerun", "18000000001", "--failed"],
        ["run-cancel", "18000000001"],
        ["workflow-run", "catalog-bump.yaml", "-f", "tool=github", "--ref", "main"],
        ["workflow-run", "catalog-bump.yaml", "--ref=main", "-Fn=1"],
        [
            "workflow-run",
            "delivery-drift.yaml",
            "-rmain",
            "--raw-field",
            "a=b",
            "--field=c=d",
        ],
        [
            "issue-create",
            "--title",
            "two words",
            "--body-file",
            "issue.md",
            "--label",
            "ci",
        ],
        ["issue-create", "-t", "t", "-b", "a body"],
        ["issue-create", "-tt", "-Fbody.md"],
        ["issue-comment", "7", "--body-file", "note.md"],
        ["issue-close", "7", "--reason", "not planned", "--comment", "superseded"],
        ["pr-create", "--title", "two words", "--body-file", "pr.md", "--draft"],
        ["pr-create", "--title", "t", "--label", "agent-fast-lane"],
        ["pr-create", "--title", "t", "--label=agent-fast-lane"],
        ["pr-create", "--title", "t", "-l", "agent-fast-lane"],
        ["pr-create", "--title", "t", "-lci, agent-fast-lane"],
        ["pr-create", "--title", "t", "--label", "ci"],
        ["pr-create"],
        ["pr-create", "--agent", "beacon", "--title", "t"],
        ["pr-edit", "--agent", "scout", "12", "--title", "t"],
    ]
    for a in passthrough:
        yield case(" ".join(a), a)
    yield case(
        "gh's exit status comes through", ["pr-ready", "12"], {"FAKE_GH_EXIT": "3"}
    )
    yield case(
        "AGENT_APP_AGENT picks the app",
        ["pr-ready", "12"],
        {"AGENT_APP_AGENT": "beacon"},
    )
    yield case("GH_BIN picks gh", ["pr-ready", "12"], {"GH_BIN": "{root}/bin/gh"})
    yield case("GH_BIN not found", ["pr-ready", "12"], {"GH_BIN": "no-such-gh"})
    yield case(
        "caller dir missing",
        ["pr-ready", "12"],
        {"BUILD_WORKING_DIRECTORY": "{root}/gone"},
    )
    yield case(
        "caller dir unset", ["pr-ready", "12"], {"BUILD_WORKING_DIRECTORY": None}
    )

    # --- refusals -------------------------------------------------------------
    refused = [
        ["pr-create", "--agent"],
        ["pr-edit"],
        ["pr-edit", "--agent", "beacon", "--title", "t"],
        ["pr-ready", "--agent", ""],
        ["pr-comment", "12"],
        ["pr-comment", "--body", "b"],
        ["pr-review", "--approve"],
        ["pr-review", "12"],
        ["pr-review", "12", "--approve", "--request-changes", "-b", "x"],
        ["pr-review", "12", "-ac", "-b", "x"],
        ["pr-review", "12", "--comment"],
        ["pr-review", "12", "--request-changes"],
        ["pr-review", "12", "-r"],
        ["pr-review", "12", "--approve", "--body"],
        ["pr-review", "12", "--approve", "-R"],
        ["pr-review", "12", "--approve", "--web"],
        ["pr-review", "12", "-aw"],
        ["issue-create", "--body-file", "issue.md"],
        ["issue-create", "--title", "t"],
        ["issue-create", "--title", "t", "--body", "b", "--repo", "other/repo"],
        ["issue-create", "--title", "t", "--body", "b", "-Rother/repo"],
        ["issue-create", "--title", "t", "--body", "b", "--web"],
        ["issue-create", "-w"],
        ["issue-comment", "7"],
        ["issue-comment", "--body", "b"],
        ["issue-comment", "7", "--body", "b", "--repo", "other/repo"],
        ["issue-close"],
        ["issue-close", "7", "-R", "other/repo"],
        ["run-rerun", "not-a-number"],
        ["run-rerun"],
        ["run-rerun", "12a"],
        ["run-rerun", "--agent", "beacon", "1"],
        ["run-cancel", "--agent", "scout", "1"],
        ["workflow-run"],
        ["workflow-run", "--agent", "forge", "catalog-bump.yaml"],
        ["workflow-run", "tabula-deploy.yaml"],
        ["workflow-run", "catalog-bump"],
        ["workflow-run", "catalog-bump.yaml.bak"],
        ["workflow-run", "../catalog-bump.yaml"],
        ["workflow-run", "catalog-bump.yaml", "--ref", "feature"],
        ["workflow-run", "catalog-bump.yaml", "--ref=dev"],
        ["workflow-run", "catalog-bump.yaml", "-r", "feature"],
        ["workflow-run", "catalog-bump.yaml", "-rfeature"],
        ["workflow-run", "catalog-bump.yaml", "--ref", "refs/heads/main"],
        ["workflow-run", "catalog-bump.yaml", "--ref"],
        ["workflow-run", "catalog-bump.yaml", "-f"],
        ["workflow-run", "catalog-bump.yaml", "-R", "o/r"],
        ["workflow-run", "catalog-bump.yaml", "-Ro/r"],
        ["workflow-run", "catalog-bump.yaml", "--repo", "o/r"],
        ["workflow-run", "catalog-bump.yaml", "--repo=o/r"],
        ["workflow-run", "catalog-bump.yaml", "--json"],
        ["pr-enqueue"],
        ["pr-enqueue", "--squash"],
        ["pr-hold"],
        ["pr-hold", "12", "--admin"],
        ["pr-hold", "12", "--label", "x"],
        ["pr-hold", "12", "--reason"],
        ["pr-hold", "12", "--repo"],
        ["pr-unhold", "12", "--reason", "r"],
        ["pr-unhold"],
        ["branch-delete"],
        ["branch-delete", "--agent", "x"],
    ]
    for given in [
        "--admin",
        "--admin=true",
        "--squash --admin",
        "--rebase",
        "--merge=1",
        "-m",
        "-sm",
        "-dr",
        "-ms",
        "--disable-auto",
    ]:
        refused.append(["pr-enqueue", "12"] + given.split())
    for a in refused:
        yield case("refused: " + " ".join(a), a)

    # --- the committed files, and their test-only overrides --------------------
    def evil(r):
        setup(r)
        write(r + "/allow.txt", "tabula-deploy.yaml\n")
        write(r + "/perms.tsv", "beacon\tactions\twrite\n")

    yield case(
        "outside test: WORKFLOW_ALLOWLIST ignored",
        ["workflow-run", "tabula-deploy.yaml"],
        {"WORKFLOW_ALLOWLIST": "{root}/allow.txt"},
        s=evil,
    )
    yield case(
        "in test: WORKFLOW_ALLOWLIST honoured",
        ["workflow-run", "tabula-deploy.yaml"],
        dict(IN_TEST, WORKFLOW_ALLOWLIST="{root}/allow.txt"),
        s=evil,
    )
    yield case(
        "in test (TEST_SRCDIR): WORKFLOW_ALLOWLIST honoured",
        ["workflow-run", "tabula-deploy.yaml"],
        {"TEST_SRCDIR": "/x", "WORKFLOW_ALLOWLIST": "{root}/allow.txt"},
        s=evil,
    )
    yield case(
        "outside test: AGENT_PERMISSIONS ignored",
        ["run-cancel", "--agent", "beacon", "1"],
        {"AGENT_PERMISSIONS": "{root}/perms.tsv"},
        s=evil,
    )
    yield case(
        "in test: AGENT_PERMISSIONS honoured",
        ["run-cancel", "--agent", "beacon", "1"],
        dict(IN_TEST, AGENT_PERMISSIONS="{root}/perms.tsv"),
        s=evil,
    )
    yield case(
        "in test: permissions unreadable",
        ["run-cancel", "1"],
        dict(IN_TEST, AGENT_PERMISSIONS="{root}/none.tsv"),
    )
    yield case(
        "in test: no agent has Actions write",
        ["run-cancel", "1"],
        dict(IN_TEST, AGENT_PERMISSIONS="{root}/perms.tsv"),
        s=lambda r: setup(
            r, extra=lambda r: write(r + "/perms.tsv", "# x\nwren\tactions\tread\n")
        ),
    )
    yield case(
        "in test: several have it",
        ["run-cancel", "--agent", "scout", "1"],
        dict(IN_TEST, AGENT_PERMISSIONS="{root}/perms.tsv"),
        s=lambda r: setup(
            r,
            extra=lambda r: write(
                r + "/perms.tsv",
                "wren\tactions\twrite\npace\tactions\tadmin\nscout\tactions\tread\n",
            ),
        ),
    )
    yield case(
        "in test: a duplicated row",
        ["run-cancel", "1"],
        dict(IN_TEST, AGENT_PERMISSIONS="{root}/perms.tsv"),
        s=lambda r: setup(
            r,
            extra=lambda r: write(
                r + "/perms.tsv", "wren\tactions\twrite\nwren\tactions\twrite\n"
            ),
        ),
    )
    yield case(
        "in test: allowlist unreadable",
        ["workflow-run", "x.yaml"],
        dict(IN_TEST, WORKFLOW_ALLOWLIST="{root}/none.txt"),
    )
    yield case(
        "in test: empty allowlist",
        ["workflow-run", "x.yaml"],
        dict(IN_TEST, WORKFLOW_ALLOWLIST="{root}/allow.txt"),
        s=lambda r: setup(r, extra=lambda r: write(r + "/allow.txt", "# nothing\n")),
    )
    yield case(
        "in test: allowlist with blanks and comments",
        ["workflow-run", "b.yaml"],
        dict(IN_TEST, WORKFLOW_ALLOWLIST="{root}/allow.txt"),
        s=lambda r: setup(
            r,
            extra=lambda r: write(
                r + "/allow.txt", "a.yaml\n\n  b.yaml  trailing\n#c.yaml\n \t\n"
            ),
        ),
    )
    yield case(
        "workspace: committed files from the workspace",
        ["workflow-run", "catalog-bump.yaml"],
        {"BUILD_WORKSPACE_DIRECTORY": "{root}/ws"},
        s=lambda r: setup(
            r,
            extra=lambda r: write(
                r + "/ws/tools/agent-app/workflow-allowlist.txt", "catalog-bump.yaml\n"
            ),
        ),
    )

    # --- no token, no action ----------------------------------------------------
    for a in [
        ["pr-edit", "12", "--title", "t"],
        ["pr-comment", "12", "--body", "b"],
        ["pr-review", "12", "--approve"],
        ["pr-ready", "12"],
        ["pr-close", "12"],
        ["pr-enqueue", "12"],
        ["pr-hold", "12", "--reason", "r"],
        ["pr-unhold", "12"],
        ["run-rerun", "1"],
        ["run-cancel", "1"],
        ["workflow-run", "catalog-bump.yaml"],
        ["issue-create", "-t", "t", "-b", "b"],
        ["issue-comment", "1", "-b", "b"],
        ["issue-close", "1"],
        ["branch-delete", "old/done"],
        ["pr-create", "--title", "t"],
    ]:
        yield case("no key: " + " ".join(a), a, {"AGENT_KEY_DIR": "/nonexistent"})
    yield case(
        "unknown agent opens nothing",
        ["pr-create", "--agent", "nosuchagent", "--title", "t"],
    )
    yield case(
        "token refused opens nothing",
        ["pr-create", "--title", "t"],
        {"FAKE_CURL_EXIT": "22"},
    )
    yield case(
        "token request answers no token", ["pr-ready", "12"], {"FAKE_CURL_OUT": "{}"}
    )
    yield case("empty token", ["pr-ready", "12"], {"FAKE_CURL_OUT": '{"token":""}'})

    # --- pr-enqueue -------------------------------------------------------------
    enq = [
        ("armed", ["pr-enqueue", "12"], {"FAKE_ENQ": "enqueue-armed"}),
        ("queued", ["pr-enqueue", "12"], {"FAKE_ENQ": "enqueue-queued"}),
        ("merged on read-back", ["pr-enqueue", "12"], {"FAKE_ENQ": "enqueue-merged"}),
        (
            "neither: reads again, NOT queued",
            ["pr-enqueue", "12"],
            {"FAKE_ENQ": "enqueue-open"},
        ),
        (
            "neither, then queued",
            ["pr-enqueue", "12"],
            {"FAKE_ENQ": "enqueue-open;enqueue-queued"},
        ),
        ("read-back fails", ["pr-enqueue", "12"], {"FAKE_ENQ_FAIL": "1"}),
        (
            "three tries, sleeping 1",
            ["pr-enqueue", "12"],
            {
                "FAKE_ENQ": "enqueue-open",
                "AGENT_APP_VERIFY_TRIES": "3",
                "AGENT_APP_VERIFY_SLEEP": "1",
            },
        ),
        (
            "default tries",
            ["pr-enqueue", "12"],
            {
                "FAKE_ENQ": "enqueue-open",
                "AGENT_APP_VERIFY_TRIES": None,
                "AGENT_APP_VERIFY_SLEEP": None,
            },
        ),
        ("zero tries", ["pr-enqueue", "12"], {"AGENT_APP_VERIFY_TRIES": "0"}),
        (
            "sleep fails",
            ["pr-enqueue", "12"],
            {"FAKE_ENQ": "enqueue-open", "FAKE_SLEEP_EXIT": "130"},
        ),
        ("already merged", ["pr-enqueue", "12"], {"FAKE_HOLD": "hold-merged"}),
        ("merge fails", ["pr-enqueue", "12"], {"FAKE_MERGE_EXIT": "1"}),
        ("held", ["pr-enqueue", "12"], {"FAKE_HOLD": "hold-held"}),
        (
            "armed and labelled",
            ["pr-enqueue", "12"],
            {"FAKE_HOLD": "hold-armed-labelled"},
        ),
        (
            "queued and labelled",
            ["pr-enqueue", "12"],
            {"FAKE_HOLD": "hold-queued-labelled"},
        ),
        (
            "release-hold's hold",
            ["pr-enqueue", "12"],
            {"FAKE_HOLD": "hold-gate-dev-deploy-red"},
        ),
        (
            "beta gate's hold",
            ["pr-enqueue", "12"],
            {"FAKE_HOLD": "hold-gate-beta-not-built"},
        ),
        ("lookup fails", ["pr-enqueue", "12"], {"FAKE_VIEW_FAIL": "1"}),
        ("lookup empty", ["pr-enqueue", "12"], {"FAKE_VIEW_EMPTY": "1"}),
        ("state read fails", ["pr-enqueue", "12"], {"FAKE_HOLD_FAIL_AT": "1"}),
        (
            "args pass through",
            ["pr-enqueue", "12", "--squash", "--auto", "--match-head-commit", "abc"],
            {},
        ),
        ("-sd", ["pr-enqueue", "12", "-sd"], {}),
        ("--subject -m", ["pr-enqueue", "12", "--subject", "-m"], {}),
        ("-t -r", ["pr-enqueue", "12", "-t", "-r"], {}),
        ("--repo", ["pr-enqueue", "12", "--repo", "o/r"], {}),
        ("-Ro/r", ["pr-enqueue", "https://github.com/o/r/pull/12", "-Ro/r"], {}),
        ("--repo= then -R", ["pr-enqueue", "12", "--repo=a/b", "-R", "c/d"], {}),
        ("--agent beacon", ["pr-enqueue", "--agent", "beacon", "12"], {}),
    ]
    for name, a, e in enq:
        yield case("pr-enqueue: " + name, a, e)

    # --- pr-hold / pr-unhold ------------------------------------------------------
    hold = [
        (
            "armed PR, with a reason",
            ["pr-hold", "12", "--reason", "waiting on #120"],
            {"FAKE_HOLD": "hold-armed;hold-held;hold-held"},
        ),
        (
            "queued PR",
            ["pr-hold", "12"],
            {"FAKE_HOLD": "hold-queued;hold-queued-labelled;hold-held"},
        ),
        ("already held", ["pr-hold", "12"], {"FAKE_HOLD": "hold-held"}),
        (
            "still armed",
            ["pr-hold", "12", "--reason", "r"],
            {"FAKE_HOLD": "hold-armed;hold-armed-labelled;hold-armed-labelled"},
        ),
        (
            "disable fails, queued",
            ["pr-hold", "12", "--reason", "r"],
            {"FAKE_MERGE_EXIT": "1", "FAKE_HOLD": "hold-armed;hold-queued-labelled"},
        ),
        (
            "disable fails",
            ["pr-hold", "12"],
            {"FAKE_MERGE_EXIT": "1", "FAKE_HOLD": "hold-armed;hold-armed-labelled"},
        ),
        (
            "label fails",
            ["pr-hold", "12"],
            {"FAKE_EDIT_EXIT": "1", "FAKE_HOLD": "hold-armed"},
        ),
        ("merged", ["pr-hold", "12"], {"FAKE_HOLD": "hold-merged"}),
        (
            "dequeue fails",
            ["pr-hold", "12"],
            {"FAKE_DEQUEUE_EXIT": "1", "FAKE_HOLD": "hold-queued;hold-queued-labelled"},
        ),
        (
            "reason not posted",
            ["pr-hold", "12", "--reason=r"],
            {"FAKE_COMMENT_EXIT": "1", "FAKE_HOLD": "hold-held"},
        ),
        (
            "reason with lines",
            ["pr-hold", "12", "--reason", "a\nb `c` $d"],
            {"FAKE_HOLD": "hold-held"},
        ),
        (
            "--repo",
            ["pr-hold", "12", "-R", "o/r", "--reason", "r"],
            {"FAKE_HOLD": "hold-open;hold-held;hold-held"},
        ),
        (
            "--repo=",
            ["pr-hold", "12", "--repo=o/r"],
            {"FAKE_HOLD": "hold-armed;hold-held;hold-held"},
        ),
        ("lookup fails", ["pr-hold", "12"], {"FAKE_VIEW_FAIL": "1"}),
        ("first read fails", ["pr-hold", "12"], {"FAKE_HOLD_FAIL_AT": "1"}),
        (
            "second read fails",
            ["pr-hold", "12"],
            {"FAKE_HOLD_FAIL_AT": "2", "FAKE_HOLD": "hold-armed"},
        ),
        (
            "third read fails",
            ["pr-hold", "12"],
            {"FAKE_HOLD_FAIL_AT": "3", "FAKE_HOLD": "hold-armed;hold-held"},
        ),
        ("unhold", ["pr-unhold", "12"], {"FAKE_HOLD": "hold-open"}),
        (
            "unhold --repo",
            ["pr-unhold", "12", "--repo", "o/r"],
            {"FAKE_HOLD": "hold-open"},
        ),
        ("unhold still labelled", ["pr-unhold", "12"], {"FAKE_HOLD": "hold-held"}),
        ("unhold label fails", ["pr-unhold", "12"], {"FAKE_EDIT_EXIT": "1"}),
        ("unhold lookup fails", ["pr-unhold", "12"], {"FAKE_VIEW_FAIL": "1"}),
        ("unhold read fails", ["pr-unhold", "12"], {"FAKE_HOLD_FAIL_AT": "1"}),
    ]
    for name, a, e in hold:
        yield case("pr-hold: " + name, a, e)

    # --- branch-delete ------------------------------------------------------------
    gate = dict(
        IN_TEST, AGENT_APP_LANDED="{root}/landed.sh", FAKE_SHA_NOW=SHA, FAKE_GIT_SHA=SHA
    )
    bd = [
        ("landed branch", ["old/done"], {}),
        (
            "gate fails",
            ["old/done"],
            {"FAKE_GATE_EXIT": "1", "FAKE_GATE_SAYS": "NOT landed: 2 commits"},
        ),
        ("open PR", ["old/done"], {"FAKE_OPEN": "12"}),
        ("open PRs", ["old/done"], {"FAKE_OPEN": "12\n13\n"}),
        ("PR list fails", ["old/done"], {"FAKE_LIST_FAIL": "1"}),
        (
            "refused names",
            [
                "main",
                "refs/heads/x",
                "a..b",
                "x y",
                "-x",
                "master",
                "HEAD",
                "/abs",
                ".ok",
            ],
            {},
        ),
        ("moved", ["old/done"], {"FAKE_SHA_NOW": OTHER_SHA}),
        ("no local sha", ["old/done"], {"FAKE_GIT_SHA": ""}),
        (
            "ref read is an error body",
            ["old/done"],
            {"FAKE_SHA_NOW": '{"message":"Not Found"}'},
        ),
        ("ref read fails", ["old/done"], {"FAKE_SHA_EXIT": "1"}),
        ("queue branch, ref read junk", [QUEUE], {"FAKE_SHA_NOW": "not-a-sha"}),
        ("queue branch, ref read empty", [QUEUE], {"FAKE_SHA_NOW": ""}),
        ("delete refused", ["old/done"], {"FAKE_DELETE_EXIT": "1"}),
        ("queue branch, merged", [QUEUE], {"FAKE_STATE": "MERGED"}),
        ("queue branch, closed", [QUEUE], {"FAKE_STATE": "CLOSED"}),
        ("queue branch, open", [QUEUE], {"FAKE_STATE": "OPEN"}),
        (
            "queue branch, unreadable",
            [QUEUE],
            {"FAKE_STATE_FAIL": "1", "FAKE_STATE": ""},
        ),
        ("mixed", ["old/done", "main", "other/done"], {}),
        ("--agent atlas", ["--agent", "atlas", "old/done"], {}),
        ("gate unreadable", ["old/done"], {"AGENT_APP_LANDED": "{root}/none.sh"}),
    ]
    for name, a, e in bd:
        env = dict(gate)
        env.update(e)
        yield case(
            "branch-delete: " + name,
            ["branch-delete"] + a,
            env,
            s=lambda r: setup(r, keys=("wren", "atlas")),
        )
    yield case(
        "branch-delete: outside test the real gate runs",
        ["branch-delete", "old/done"],
        {"AGENT_APP_LANDED": "{root}/landed.sh", "FAKE_SHA_NOW": SHA},
    )


def find_jq():
    p = need_env("JQ_BIN")
    cands = [p]
    if p.startswith("external/"):
        cands.insert(0, "../" + p[len("external/") :])
    for c in cands:
        if os.path.exists(c):
            return os.path.abspath(c)
    print("jq not found at %s" % cands, file=sys.stderr)
    sys.exit(2)


def main():
    global KEY, JQ, FIXTURES, HERE
    script = need_env("AGENT_APP_SH")
    binary = need_env("AGENT_APP_RS")
    JQ = find_jq()
    HERE = os.path.dirname(os.path.abspath(script))
    FIXTURES = os.path.join(HERE, "testdata")
    kd = tempfile.mkdtemp(prefix="key.", dir=os.environ.get("TEST_TMPDIR"))
    KEY = kd + "/key.pem"
    subprocess.run(
        ["openssl", "genrsa", "-out", KEY, "2048"], check=True, capture_output=True
    )
    h = Harness("agent-app parity", script, binary)
    for c in cases():
        h.check(c)
    rc = h.finish()
    shutil.rmtree(kd, ignore_errors=True)
    return rc


if __name__ == "__main__":
    sys.exit(main())
