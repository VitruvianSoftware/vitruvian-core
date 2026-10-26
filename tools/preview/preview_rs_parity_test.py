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
"""neon-branch, provision-preview and pr-comment, the Rust ports, against
their scripts: same exit code, stdout, stderr, and the same calls to curl,
gcloud, kubectl and gh -- argv, plus what kubectl was fed on stdin -- on
every case below. The scripts' jq is the hermetic one (JQ_BIN); the ports
carry their own.

    bazel test //tools/preview:preview_rs_parity_test

The comment timestamp (`date -u`) is normalised; so is the program name in
the usage text and in bash's own diagnostics (`neon-branch.sh` against
`neon-branch`).
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
    write_exec,
)

JQ = need_env("JQ_BIN")
# $(JQ_BIN) is an execroot path (external/<repo>/jq); in runfiles the repo
# sits beside the main one.
if not os.path.exists(JQ) and JQ.startswith("external/"):
    JQ = os.path.join("..", JQ[len("external/") :])
if not os.path.exists(JQ):
    print("hermetic jq not found at %s" % JQ, file=sys.stderr)
    sys.exit(2)
JQ = os.path.abspath(JQ)

# Every fake logs its argv (one [arg] per argument) to $LOGDIR/<tool>.log.
LOG_ARGV = r"""line="$(basename "$0"):"; for a in "$@"; do line="$line [$a]"; done
[ "$(basename "$0")" = kubectl ] && [ "$1" = apply ] || printf '%s\n' "$line" >>"$LOGDIR/calls.log"
"""

CURL = (
    "#!/usr/bin/env bash\n"
    + LOG_ARGV
    + r"""
method=GET; prev=""; url=""
for a in "$@"; do [ "$prev" = -X ] && method="$a"; prev="$a"; url="$a"; done
case " $* " in
  *" -w "*)
    printf '%s' "${FAKE_SMOKE_OUT-200}"
    exit "${FAKE_SMOKE_RC:-0}" ;;
esac
for p in ${FAKE_FAIL_ON:-}; do
  case "$method $url" in *"$p"*) echo "curl: (22) The requested URL returned error: 404" >&2; exit 22 ;; esac
done
case "$method $url" in
  "POST "*/branches)  printf '%s' "${FAKE_CREATE-}" ;;
  "GET "*/branches)   printf '%s' "${FAKE_BRANCHES-}" ;;
  "DELETE "*)         printf '%s' '{"branch":{}}' ;;
  "GET "*/endpoints)  printf '%s' "${FAKE_ENDPOINTS-}" ;;
  "GET "*connection_uri*) printf '%s' "${FAKE_URI-}" ;;
  *) echo "fake curl: unexpected $method $url" >&2; exit 99 ;;
esac
"""
)

GCLOUD = (
    "#!/usr/bin/env bash\n"
    + LOG_ARGV
    + r"""
case "$*" in
  "run deploy"*)
    echo "Deploying container to Cloud Run service [$3]"
    echo "Done." >&2
    exit "${FAKE_DEPLOY_RC:-0}" ;;
  "run services describe"*)
    printf '%s\n' "${FAKE_SERVICE_URL-https://svc-abc-uc.a.run.app}"
    exit "${FAKE_DESCRIBE_RC:-0}" ;;
esac
exit 98
"""
)

KUBECTL = (
    "#!/usr/bin/env bash\n"
    + LOG_ARGV
    + r"""
case "$1" in
  create)
    printf 'apiVersion: v1\nkind: %s\nargs: %s\n' "$2" "$*"
    exit "${FAKE_CREATE_RC:-0}" ;;
  apply)
    # Logged once its input is complete: after the create feeding it.
    input="$(cat)"
    printf '%s\n--- stdin:\n%s\n' "$line" "$input" >>"$LOGDIR/calls.log"
    echo "applied"
    exit "${FAKE_APPLY_RC:-0}" ;;
esac
"""
)

GH = (
    "#!/usr/bin/env bash\n"
    + LOG_ARGV
    + r"""
if [ "$2" = "-X" ]; then
  echo '{"id": 1}'
  exit "${FAKE_WRITE_RC:-0}"
fi
[ -n "${FAKE_LIST_ERR:-}" ] && echo "gh: $FAKE_LIST_ERR" >&2
printf '%s' "${FAKE_LIST-}"
exit "${FAKE_LIST_RC:-0}"
"""
)


def fakes(jq=True, **extra):
    def setup(root):
        b = os.path.join(root, "bin")
        write_exec(os.path.join(b, "curl"), CURL)
        write_exec(os.path.join(b, "gcloud"), GCLOUD)
        write_exec(os.path.join(b, "kubectl"), KUBECTL)
        write_exec(os.path.join(b, "gh"), GH)
        if jq:
            os.symlink(JQ, os.path.join(b, "jq"))
        for name in extra.get("remove", ()):
            os.unlink(os.path.join(b, name))

    return setup


NORMALISE = [
    (rb"Usage: [^ \n]+", b"Usage: <PROG>"),
    (rb"\d{4}-\d\d-\d\d \d\d:\d\d:\d\d UTC", b"<TIMESTAMP>"),
    # bash names the script it could not start (neon-branch.sh), the port
    # its own tool (neon-branch).
    (rb"(neon-branch|pr-comment|provision-preview)\.sh", rb"\1"),
]


def case(name, args, env=None, setup=None, **kw):
    e = {"LOGDIR": "{root}"}
    e.update(env or {})
    return Case(
        name=name,
        args=args,
        env=e,
        setup=setup or fakes(),
        normalise=NORMALISE,
        **kw,
    )


# ---------------------------------------------------------------------------
# neon-branch
# ---------------------------------------------------------------------------

LIVE = ["--project-id", "prj-1", "--api-key", "KEY", "--branch-name", "app-pr-7"]
BR_MAIN = '{"id":"br-main","name":"main"}'
BR_PR = '{"id":"br-pr7","name":"app-pr-7","parent_id":"br-main"}'
BRANCHES = '{"branches":[%s,%s]}' % (BR_MAIN, BR_PR)
BRANCHES_NO_PR = '{"branches":[%s]}' % BR_MAIN
ENDPOINTS = (
    '{"endpoints":[{"branch_id":"br-x","host":"ep-x.neon.tech"},'
    '{"branch_id":"br-pr7","host":"ep-pr7.neon.tech"},'
    '{"branch_id":"br-new","host":"ep-new.neon.tech"},'
    '{"branch_id":"br-pr7","host":"ep-second.neon.tech"}]}'
)
URI = '{"uri":"postgresql://neondb_owner:pw@ep-pr7.neon.tech/neondb?sslmode=require"}'
CREATED = '{"branch":{"id":"br-new","name":"app-pr-7"},"endpoints":[]}'


def neon_cases():
    c = []
    c.append(case("no args", []))
    c.append(case("help", ["-h"]))
    c.append(case("help after action", ["create", "--help"]))
    c.append(case("unknown option", ["create", "--bogus"]))
    c.append(case("empty option", ["get", ""]))
    c.append(case("action not first", ["--dry-run", "create"]))
    c.append(case("only options, no action", ["--dry-run"]))
    for opt in [
        "--project-id",
        "--api-key",
        "--branch-name",
        "--parent-id",
        "--api-url",
        "--format",
    ]:
        c.append(case("missing value " + opt, ["create", opt]))
    c.append(case("dry-run create bare", ["create", "--dry-run"]))
    c.append(
        case(
            "dry-run create full",
            ["create", "--dry-run", "--parent-id", "dev"] + LIVE,
        )
    )
    c.append(
        case(
            "dry-run create from env",
            ["create", "--dry-run"],
            env={
                "NEON_PROJECT_ID": "env-prj",
                "NEON_BRANCH_NAME": 'we"ird\\name',
                "NEON_PARENT_ID": "env-parent",
            },
        )
    )
    c.append(case("dry-run delete", ["delete", "--dry-run", "--branch-name", "b"]))
    c.append(case("dry-run delete bare", ["delete", "--dry-run"]))
    c.append(case("dry-run get", ["get", "--dry-run"]))
    c.append(case("live missing project", ["create", "--api-key", "k"]))
    c.append(case("live missing key", ["delete", "--project-id", "p"]))
    c.append(
        case("live missing branch", ["get", "--project-id", "p", "--api-key", "k"])
    )
    c.append(
        case(
            "live from env",
            ["get"],
            env={
                "NEON_PROJECT_ID": "prj-env",
                "NEON_API_KEY": "KEY",
                "NEON_BRANCH_NAME": "app-pr-7",
                "FAKE_BRANCHES": BRANCHES,
                "FAKE_ENDPOINTS": ENDPOINTS,
                "FAKE_URI": URI,
            },
        )
    )

    ok = {"FAKE_BRANCHES": BRANCHES, "FAKE_ENDPOINTS": ENDPOINTS, "FAKE_URI": URI}
    c.append(case("create: branch exists", ["create"] + LIVE, env=ok))
    c.append(
        case("create: exists, url format", ["create", "--format", "url"] + LIVE, env=ok)
    )
    c.append(
        case(
            "create: exists, other format",
            ["create", "--format", "yaml"] + LIVE,
            env=ok,
        )
    )
    new = dict(ok, FAKE_BRANCHES=BRANCHES_NO_PR, FAKE_CREATE=CREATED)
    c.append(case("create: new from main by name", ["create"] + LIVE, env=new))
    c.append(
        case(
            "create: new from parent by id",
            ["create", "--parent-id", "br-main"] + LIVE,
            env=new,
        )
    )
    c.append(
        case(
            "create: parent not found",
            ["create", "--parent-id", "nope"] + LIVE,
            env=new,
        )
    )
    c.append(
        case(
            "create: parent id is null",
            ["create"] + LIVE,
            env=dict(new, FAKE_BRANCHES='{"branches":[{"id":null,"name":"main"}]}'),
        )
    )
    c.append(
        case(
            "create: parent id is an object",
            ["create"] + LIVE,
            env=dict(
                new,
                FAKE_BRANCHES='{"branches":[{"name":"main","id":{"z":1,"a":[2,"x"]}}]}',
            ),
        )
    )
    c.append(
        case(
            "create: POST fails",
            ["create"] + LIVE,
            env=dict(new, FAKE_FAIL_ON="POST"),
        )
    )
    c.append(
        case(
            "create: POST answers without a branch",
            ["create"] + LIVE,
            env=dict(new, FAKE_CREATE='{"error":"x"}'),
        )
    )
    c.append(
        case(
            "create: POST answers nothing",
            ["create"] + LIVE,
            env=dict(new, FAKE_CREATE=""),
        )
    )
    c.append(
        case(
            "create: POST answers a string branch",
            ["create"] + LIVE,
            env=dict(new, FAKE_CREATE='{"branch":"br"}'),
        )
    )
    c.append(
        case(
            "create: no uri -> built from host",
            ["create"] + LIVE,
            env=dict(ok, FAKE_URI='{"uri":null}'),
        )
    )
    c.append(
        case(
            "create: uri false, no endpoint",
            ["create"] + LIVE,
            env=dict(ok, FAKE_URI='{"uri":false}', FAKE_ENDPOINTS='{"endpoints":[]}'),
        )
    )
    c.append(
        case(
            "create: uri is an array",
            ["create"] + LIVE,
            env=dict(ok, FAKE_URI="[1,2]"),
        )
    )
    c.append(
        case(
            "create: list fails (swallowed, then parent lookup fails)",
            ["create"] + LIVE,
            env=dict(ok, FAKE_FAIL_ON="GET*/branches"),
        )
    )
    c.append(
        case(
            "create: endpoints fail (swallowed)",
            ["create"] + LIVE,
            env=dict(ok, FAKE_FAIL_ON="endpoints"),
        )
    )
    c.append(
        case(
            "create: connection_uri fails (fatal)",
            ["create"] + LIVE,
            env=dict(ok, FAKE_FAIL_ON="connection_uri"),
        )
    )
    c.append(
        case(
            "create: branches is null (jq error, fatal)",
            ["create"] + LIVE,
            env=dict(ok, FAKE_BRANCHES='{\n  "branches": null\n}\n\n'),
        )
    )
    c.append(
        case(
            "create: a branch is a long string",
            ["create"] + LIVE,
            env=dict(
                ok,
                FAKE_BRANCHES='{"branches":[%s,"%s"]}' % (BR_MAIN, "s" * 40),
            ),
        )
    )
    c.append(
        case(
            "create: endpoints not a list",
            ["create"] + LIVE,
            env=dict(ok, FAKE_ENDPOINTS='{"endpoints":"é€aaaaaaaaaaaaaaaaaaa"}'),
        )
    )
    c.append(
        case(
            "create: endpoint entry is a number",
            ["create"] + LIVE,
            env=dict(ok, FAKE_ENDPOINTS='{"endpoints":[7]}'),
        )
    )
    c.append(
        case(
            "create: response stream of two texts",
            ["create"] + LIVE,
            env=dict(ok, FAKE_BRANCHES=BRANCHES + "\n" + '{"branches":[%s]}' % BR_PR),
        )
    )
    c.append(
        case(
            "create: branches as an object, in input order",
            ["create"] + LIVE,
            env=dict(
                ok,
                FAKE_BRANCHES='{"branches":{"z":%s,"a":{"id":"br-x","name":"app-pr-7"}}}'
                % BR_PR,
            ),
        )
    )
    c.append(
        case(
            "create: response is -n (echo option)",
            ["create"] + LIVE,
            env=dict(new, FAKE_BRANCHES="-n"),
        )
    )
    c.append(
        case(
            "create: escapes in values",
            [
                "create",
                "--branch-name",
                'a"b\\c\x01\x7fé\tz',
                "--project-id",
                "p",
                "--api-key",
                "k",
            ],
            env=dict(
                ok,
                FAKE_BRANCHES='{"branches":[{"id":"i\\"d\\u0002","name":"a\\"b\\\\c\\u0001\\u007f\\u00e9\\tz"}]}',
                FAKE_ENDPOINTS='{"endpoints":[{"branch_id":"i\\"d\\u0002","host":"h\\u001fé"}]}',
            ),
        )
    )
    c.append(
        case(
            "create: numeric branch id",
            ["create"] + LIVE,
            env=dict(ok, FAKE_BRANCHES='{"branches":[{"id":42,"name":"app-pr-7"}]}'),
        )
    )
    c.append(
        case(
            "create: api url trailing slash, path from env",
            ["create", "--api-url", "https://neon.example/api/"] + LIVE,
            env=ok,
        )
    )
    c.append(
        case(
            "create: NEON_API_URL",
            ["create"] + LIVE,
            env=dict(ok, NEON_API_URL="http://local:1"),
        )
    )
    c.append(
        case(
            "create: curl missing",
            ["create"] + LIVE,
            env=dict(ok, PATH="{root}/bin:" + path_without("curl")),
            setup=fakes(remove=["curl"]),
        )
    )
    c.append(
        case(
            "create: two branches share the name",
            ["create"] + LIVE,
            env=dict(
                ok,
                FAKE_BRANCHES='{"branches":[%s,{"id":"br-dup","name":"app-pr-7"}]}'
                % BR_PR,
            ),
        )
    )
    c.append(case("delete: found", ["delete"] + LIVE, env=ok))
    c.append(
        case(
            "delete: not found",
            ["delete"] + LIVE,
            env=dict(ok, FAKE_BRANCHES=BRANCHES_NO_PR),
        )
    )
    c.append(
        case(
            "delete: DELETE fails",
            ["delete"] + LIVE,
            env=dict(ok, FAKE_FAIL_ON="DELETE"),
        )
    )
    c.append(
        case(
            "delete: list fails",
            ["delete"] + LIVE,
            env=dict(ok, FAKE_FAIL_ON="GET*/branches"),
        )
    )
    c.append(
        case(
            "delete: list is garbage-free but wrong shape",
            ["delete"] + LIVE,
            env=dict(ok, FAKE_BRANCHES='["x"]'),
        )
    )
    c.append(case("get: found", ["get"] + LIVE, env=ok))
    c.append(case("get: url", ["get", "--format", "url"] + LIVE, env=ok))
    c.append(case("get: no uri", ["get"] + LIVE, env=dict(ok, FAKE_URI="{}")))
    c.append(
        case(
            "get: not found", ["get"] + LIVE, env=dict(ok, FAKE_BRANCHES=BRANCHES_NO_PR)
        )
    )
    c.append(
        case(
            "get: endpoints fail",
            ["get"] + LIVE,
            env=dict(ok, FAKE_FAIL_ON="endpoints"),
        )
    )
    return c


# ---------------------------------------------------------------------------
# provision-preview
# ---------------------------------------------------------------------------

LIVE_CR = [
    "--app",
    "tabula-api",
    "--pr",
    "142",
    "--image-digest",
    "sha256:abc",
    "--project",
    "prj-x",
]


def provision_cases():
    c = []
    c.append(case("no args", []))
    c.append(case("help", ["--help"]))
    c.append(case("unknown option", ["--app", "a", "--wat"]))
    c.append(case("app only", ["--app", "a"]))
    for opt in [
        "--app",
        "--pr",
        "--image-digest",
        "--mode",
        "--project",
        "--region",
        "--neon-project-id",
        "--smoke-path",
        "--domain-base",
    ]:
        c.append(case("missing value " + opt, ["--app", "a", opt]))
    c.append(
        case("dry-run cloud-run", ["--app", "tabula-api", "--pr", "142", "--dry-run"])
    )
    c.append(
        case(
            "dry-run with neon, region from env",
            [
                "--app",
                "tabula-api",
                "--pr",
                "142",
                "--neon-project-id",
                "n",
                "--dry-run",
            ],
            env={"GCP_REGION": "europe-west1"},
        )
    )
    c.append(
        case(
            "dry-run neon from env, k8s",
            ["--app", "x", "--pr", "1", "--mode", "k8s", "--dry-run"],
            env={"NEON_PROJECT_ID": "n"},
        )
    )
    c.append(
        case(
            "dry-run unknown mode, custom smoke and domain",
            [
                "--app",
                "x",
                "--pr",
                "1",
                "--mode",
                "fargate",
                "--dry-run",
                "--smoke-path",
                "/ready",
                "--domain-base",
                "p.example",
            ],
        )
    )
    c.append(
        case(
            "dry-run quotes in values (jq escapes them)",
            [
                "--app",
                'we"ird\\',
                "--pr",
                "1\t2",
                "--dry-run",
                "--neon-project-id",
                "n",
            ],
        )
    )
    c.append(
        case(
            "dry-run without jq (heredoc output)",
            ["--app", 'we"ird', "--pr", "7", "--dry-run", "--neon-project-id", "n"],
            env={"PATH": "{root}/bin:" + path_without("jq")},
            setup=fakes(jq=False),
        )
    )
    c.append(
        case(
            "dry-run without jq, no neon",
            ["--app", "a", "--pr", "7", "--dry-run"],
            env={"PATH": "{root}/bin:" + path_without("jq")},
            setup=fakes(jq=False),
        )
    )
    c.append(case("live: missing digest", ["--app", "a", "--pr", "1"]))
    c.append(
        case(
            "live: missing project",
            ["--app", "a", "--pr", "1", "--image-digest", "d"],
        )
    )
    c.append(
        case(
            "live: project from env",
            ["--app", "a", "--pr", "1", "--image-digest", "d"],
            env={"GCP_PROJECT_ID": "env-prj"},
        )
    )
    c.append(case("live cloud-run", LIVE_CR))
    c.append(
        case(
            "live cloud-run: smoke 500",
            LIVE_CR,
            env={"FAKE_SMOKE_OUT": "500"},
        )
    )
    c.append(
        case(
            "live cloud-run: smoke 302, trailing slash url",
            LIVE_CR + ["--smoke-path", "/x"],
            env={"FAKE_SMOKE_OUT": "302", "FAKE_SERVICE_URL": "https://s.run.app/"},
        )
    )
    c.append(
        case(
            "live cloud-run: curl cannot connect",
            LIVE_CR,
            env={"FAKE_SMOKE_OUT": "000", "FAKE_SMOKE_RC": "7"},
        )
    )
    c.append(
        case(
            "live cloud-run: deploy fails",
            LIVE_CR,
            env={"FAKE_DEPLOY_RC": "3"},
        )
    )
    c.append(
        case(
            "live cloud-run: describe fails",
            LIVE_CR,
            env={"FAKE_DESCRIBE_RC": "4"},
        )
    )
    c.append(
        case(
            "live cloud-run: gcloud missing",
            LIVE_CR,
            env={"PATH": "{root}/bin:" + path_without("gcloud")},
            setup=fakes(remove=["gcloud"]),
        )
    )
    neon_ok = {
        "NEON_API_KEY": "KEY",
        "FAKE_BRANCHES": '{"branches":[{"id":"br-1","name":"tabula-api-pr-142"}]}',
        "FAKE_ENDPOINTS": '{"endpoints":[{"branch_id":"br-1","host":"ep-1.neon.tech"}]}',
        "FAKE_URI": '{"uri":"postgresql://u:p@ep-1.neon.tech/neondb"}',
    }
    c.append(
        case(
            "live cloud-run with neon",
            LIVE_CR + ["--neon-project-id", "neon-prj"],
            env=neon_ok,
        )
    )
    c.append(
        case(
            "live with neon: neon-branch fails (no key)",
            LIVE_CR + ["--neon-project-id", "neon-prj"],
            env=dict(neon_ok, NEON_API_KEY=""),
        )
    )
    c.append(
        case(
            "live with neon: neon-branch jq error",
            LIVE_CR + ["--neon-project-id", "neon-prj"],
            env=dict(neon_ok, FAKE_BRANCHES='{"branches":1}'),
        )
    )
    c.append(
        case(
            "live k8s",
            ["--app", "a", "--pr", "9", "--mode", "k8s"],
        )
    )
    c.append(
        case(
            "live k8s with neon",
            [
                "--app",
                "tabula-api",
                "--pr",
                "142",
                "--mode",
                "k8s",
                "--neon-project-id",
                "n",
            ],
            env=neon_ok,
        )
    )
    c.append(
        case(
            "live k8s: apply fails",
            ["--app", "a", "--pr", "9", "--mode", "k8s"],
            env={"FAKE_APPLY_RC": "5"},
        )
    )
    c.append(
        case(
            "live k8s: create fails",
            ["--app", "a", "--pr", "9", "--mode", "k8s"],
            env={"FAKE_CREATE_RC": "6"},
        )
    )
    c.append(
        case(
            "live other mode",
            ["--app", "a", "--pr", "9", "--mode", "nomad"],
        )
    )
    return c


# ---------------------------------------------------------------------------
# pr-comment
# ---------------------------------------------------------------------------

READY = [
    "--pr",
    "142",
    "--app",
    "tabula",
    "--status",
    "ready",
    "--preview-url",
    "https://pr-142.tabula.preview.example",
    "--service-name",
    "tabula-api-pr-142",
    "--db-branch",
    "tabula-pr-142",
]


def comment_cases():
    c = []
    c.append(case("no args", []))
    c.append(case("help", ["-h"]))
    c.append(case("unknown option", ["--pr", "1", "--nope"]))
    c.append(case("pr only", ["--pr", "1"]))
    for opt in [
        "--pr",
        "--app",
        "--status",
        "--preview-url",
        "--service-name",
        "--db-branch",
        "--repo",
    ]:
        c.append(case("missing value " + opt, ["--pr", "1", opt]))
    for st in ["provisioning", "ready", "failed", "teardown"]:
        c.append(
            case(
                "dry-run " + st,
                ["--pr", "142", "--app", "tabula", "--status", st, "--dry-run"],
            )
        )
    c.append(case("dry-run default status", ["--pr", "1", "--app", "a", "--dry-run"]))
    c.append(case("dry-run full ready", READY + ["--dry-run"]))
    c.append(case("unknown status", ["--pr", "1", "--app", "a", "--status", "gone"]))
    c.append(
        case(
            "unknown status dry-run",
            ["--pr", "1", "--app", "a", "--status", "", "--dry-run"],
        )
    )
    c.append(
        case(
            "app with trailing newlines",
            ["--pr", "1", "--app", "a\n\n", "--status", "failed", "--dry-run"],
        )
    )
    c.append(case("live: create", READY))
    c.append(case("live: update", READY, env={"FAKE_LIST": "111\n222\n"}))
    c.append(
        case(
            "live: repo from env, update",
            ["--pr", "3", "--app", "x", "--status", "teardown"],
            env={"GITHUB_REPOSITORY": "o/r", "FAKE_LIST": "9"},
        )
    )
    c.append(case("live: --repo", READY + ["--repo", "a/b"]))
    c.append(
        case(
            "live: list fails",
            READY,
            env={"FAKE_LIST_RC": "1", "FAKE_LIST_ERR": "HTTP 404"},
        )
    )
    c.append(
        case("live: patch fails", READY, env={"FAKE_LIST": "5", "FAKE_WRITE_RC": "2"})
    )
    c.append(case("live: post fails", READY, env={"FAKE_WRITE_RC": "4"}))
    c.append(
        case(
            "live: gh missing",
            READY,
            env={"PATH": "{root}/bin:" + path_without("gh")},
            setup=fakes(remove=["gh"]),
        )
    )
    return c


def main() -> int:
    rc = 0
    for title, sh, rs, cases in [
        ("neon-branch", "NEON_BRANCH_SH", "NEON_BRANCH_RS", neon_cases()),
        (
            "provision-preview",
            "PROVISION_PREVIEW_SH",
            "PROVISION_PREVIEW_RS",
            provision_cases(),
        ),
        ("pr-comment", "PR_COMMENT_SH", "PR_COMMENT_RS", comment_cases()),
    ]:
        print("== %s" % title)
        h = Harness(title + " parity", need_env(sh), need_env(rs))
        for cs in cases:
            h.check(cs)
        rc |= h.finish()
    return rc


if __name__ == "__main__":
    sys.exit(main())
