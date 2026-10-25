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
"""cloud-run, the Rust port, against cloud-run.sh: same exit code, stdout,
stderr, and the same calls -- every pulumi (through the workspace's
tools/pulumi/pulumi-cmd.sh), gcloud, curl and custom smoke run, with argv
AND the <PREFIX>_ variables each was handed -- on every case below.

    bazel test //tools/deploy:cloud_run_rs_parity_test

The script filters gcloud's JSON with jq (the hermetic one, JQ_BIN, linked
into each sandbox's bin/); the port parses it with serde_json.
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

ENVDUMP = r"""
  for v in TABULA_IMAGE_DIGEST TABULA_IMAGE_TAG TABULA_STABLE_REVISION TABULA_PROMOTE CAND; do
    eval "printf ' %s=%s' $v \"\${$v-<unset>}\""
  done
  printf '\n'
"""

# The pulumi wrapper the tool runs as `bash <ws>/tools/pulumi/pulumi-cmd.sh
# <dir> <args>`.
PULUMI_CMD = (
    r"""#!/usr/bin/env bash
mkdir -p "$LOGDIR"
{ printf 'pulumi-cmd:'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; printf '  env:'"""
    + ENVDUMP
    + r"""} >>"$LOGDIR/calls.log"
shift
case "$1 $2" in
  "stack select")
    echo "select out"; echo "select err" >&2
    if [ "${FAKE_STACK_MISSING:-0}" = 1 ] && [ "${4:-}" != "-c" ]; then exit 6; fi
    exit "${FAKE_SELECT_RC:-0}" ;;
  "stack output")
    echo "output err" >&2
    [ -n "${FAKE_SERVICE_URL+x}" ] && printf '%s\n\n' "$FAKE_SERVICE_URL"
    exit "${FAKE_OUTPUT_RC:-0}" ;;
  "up --stack")
    echo "pulumi up: updating"; echo "pulumi up: warning" >&2
    if [ "${FAKE_UP_FAIL:-}" = "$TABULA_PROMOTE" ]; then echo "up failed" >&2; exit 3; fi
    exit 0 ;;
esac
echo "unexpected: $*" >&2; exit 99
"""
)

GCLOUD = (
    r"""#!/usr/bin/env bash
mkdir -p "$LOGDIR"
{ printf 'gcloud:'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; printf '  env:'"""
    + ENVDUMP
    + r"""} >>"$LOGDIR/calls.log"
case "$*" in
  *--format=json*)
    echo "json noise" >&2
    [ -f "$FAKE_JSON" ] && cat "$FAKE_JSON"
    exit "${FAKE_JSON_RC:-0}" ;;
  *)
    [ -n "${FAKE_GERR:-}" ] && printf '%b\n' "$FAKE_GERR" >&2
    [ -n "${FAKE_STABLE:-}" ] && printf '%s\n\n' "$FAKE_STABLE"
    exit "${FAKE_GRC:-0}" ;;
esac
"""
)

CURL = (
    r"""#!/usr/bin/env bash
mkdir -p "$LOGDIR"
{ printf 'curl:'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; printf '  env:'"""
    + ENVDUMP
    + r"""} >>"$LOGDIR/calls.log"
echo "curl body"
[ "${FAKE_CURL_RC:-0}" = 0 ] || echo "curl: (22) The requested URL returned error: 503" >&2
exit "${FAKE_CURL_RC:-0}"
"""
)

SMOKE_FILE = r"""echo "smoke file running against $CAND"
printf 'smoke-file CAND=%s PROMOTE=%s\n' "$CAND" "${TABULA_PROMOTE-}" >>"$LOGDIR/calls.log"
exit "${FAKE_SMOKE_RC:-0}"
"""

JSON_CAND = '{"status":{"traffic":[{"revisionName":"rev-old","percent":100},{"tag":"candidate","url":"https://cand.example","percent":0}]}}\n'


def setup_factory(json=None, ws=True, pulumi_cmd=True, curl=True, gcloud=True):
    def setup(root):
        os.symlink(JQ, os.path.join(root, "bin", "jq"))
        if gcloud:
            write_exec(root + "/bin/gcloud", GCLOUD)
        if curl:
            write_exec(root + "/bin/curl", CURL)
        if json is not None:
            write(root + "/fake.json", json)
        if ws:
            os.makedirs(root + "/ws/tools/pulumi")
            write(root + "/ws/smoke/check.sh", SMOKE_FILE)
            if pulumi_cmd:
                write(root + "/ws/tools/pulumi/pulumi-cmd.sh", PULUMI_CMD)

    return setup


BASE_ENV = {
    "LOGDIR": "{root}/log",
    "BUILD_WORKSPACE_DIRECTORY": "{root}/ws",
    "FAKE_JSON": "{root}/fake.json",
}

COMMON = [
    "--pulumi-dir",
    "tabula/infra/app",
    "--service",
    "tabula-api",
    "--env",
    "development",
    "--env-prefix",
    "TABULA",
    "--project",
    "prj-x",
    "--region",
    "us-central1",
]
DIGEST = ["--image-digest", "reg/app@sha256:abc"]


def case(name, args, env=None, setup=None, **kw):
    e = dict(BASE_ENV)
    e.update(env or {})
    return Case(
        name=name,
        args=args,
        env=e,
        setup=setup or setup_factory(),
        **kw,
    )


def cases():
    # --- argument guards -------------------------------------------------
    yield case("no args", [])
    yield case("--help", ["--help"])
    yield case("-h after flags", COMMON + ["-h"])
    yield case("unknown argument", COMMON + ["--bogus", "x"])
    req = [
        ("--pulumi-dir", 0),
        ("--service", 2),
        ("--env", 4),
        ("--env-prefix", 6),
        ("--project", 8),
        ("--region", 10),
    ]
    for flag, i in req:
        args = COMMON[:i] + COMMON[i + 2 :] + DIGEST + ["--dry-run"]
        yield case("missing " + flag, args)
    yield case("empty --env value", COMMON[:5] + [""] + COMMON[6:] + DIGEST)
    yield case("bad --phase", COMMON + DIGEST + ["--phase", "bogus", "--dry-run"])
    yield case("empty --phase", COMMON + DIGEST + ["--phase", ""])
    yield case("missing image ref", COMMON + ["--dry-run"])
    yield case("flag without its value at the end", COMMON + DIGEST + ["--phase"])
    yield case("--env-prefix without value", ["--env-prefix"])
    yield case(
        "--custom-smoke-script-file without bazel run",
        COMMON + DIGEST + ["--custom-smoke-script-file", "smoke/check.sh"],
        env={"BUILD_WORKSPACE_DIRECTORY": None},
    )
    yield case(
        "--custom-smoke-script-file missing file",
        COMMON + DIGEST + ["--custom-smoke-script-file", "smoke/nope.sh"],
    )
    yield case(
        "--custom-smoke-script-file with no value",
        COMMON + DIGEST + ["--custom-smoke-script-file"],
    )

    # --- dry runs ----------------------------------------------------------
    dry = COMMON + DIGEST + ["--dry-run"]
    yield case("dry all, steady state", dry + ["--stable-revision", "rev-old"])
    yield case("dry all, first deploy", dry)
    yield case(
        "dry all, --refresh", dry + ["--stable-revision", "rev-old", "--refresh"]
    )
    for ph in ("candidate", "smoke", "promote"):
        yield case("dry " + ph, dry + ["--phase", ph, "--stable-revision", "r1"])
    yield case(
        "dry image tag",
        COMMON + ["--image-tag", "v1", "--dry-run", "--phase", "candidate"],
    )
    yield case(
        "dry digest beats tag",
        COMMON + DIGEST + ["--image-tag", "v1", "--dry-run", "--phase", "candidate"],
    )
    yield case(
        "dry invalid prefix (export refuses it)",
        COMMON[:7] + ["A-B"] + COMMON[8:] + DIGEST + ["--dry-run"],
    )
    yield case(
        "dry prefix with '='",
        COMMON[:7]
        + ["A=B"]
        + COMMON[8:]
        + DIGEST
        + ["--dry-run", "--phase", "candidate"],
    )
    yield case(
        "dry stable revision that looks like an echo option",
        dry + ["--stable-revision", "-n"],
    )
    yield case(
        "dry digest with '=' and newline",
        COMMON + ["--image-digest", "a=b\nc=d", "--dry-run", "--phase", "promote"],
    )
    yield case(
        "dry custom smoke file read",
        dry + ["--custom-smoke-script-file", "smoke/check.sh", "--smoke-path", "/h"],
    )

    # --- real runs, faked tools -------------------------------------------
    real = COMMON + DIGEST
    yield case(
        "not under bazel run",
        real + ["--phase", "candidate"],
        env={"BUILD_WORKSPACE_DIRECTORY": None},
    )
    yield case(
        "empty BUILD_WORKSPACE_DIRECTORY",
        real + ["--phase", "candidate"],
        env={"BUILD_WORKSPACE_DIRECTORY": ""},
    )
    yield case(
        "candidate, missing stack is created, stable from gcloud",
        real + ["--phase", "candidate"],
        env={"FAKE_STACK_MISSING": "1", "FAKE_STABLE": "rev-live"},
    )
    yield case(
        "candidate, stack select errors both ways",
        real + ["--phase", "candidate"],
        env={"FAKE_SELECT_RC": "255", "FAKE_STABLE": "rev-live"},
    )
    yield case(
        "NOT_FOUND is a first deploy",
        real + ["--phase", "candidate"],
        env={
            "FAKE_GRC": "1",
            "FAKE_GERR": "ERROR: (gcloud.run.services.describe) NOT_FOUND: Requested entity was not found.",
        },
    )
    yield case(
        "PERMISSION_DENIED is reported, then carried on as a first deploy",
        real + ["--phase", "candidate"],
        env={
            "FAKE_GRC": "1",
            "FAKE_GERR": "ERROR: PERMISSION_DENIED: caller lacks permission\\nsecond line",
        },
    )
    yield case(
        "gcloud fails with no stderr",
        real + ["--phase", "candidate"],
        env={"FAKE_GRC": "2"},
    )
    yield case(
        "gcloud rc=0 with stderr noise",
        real + ["--phase", "candidate"],
        env={"FAKE_GERR": "WARNING: something", "FAKE_STABLE": "rev-9"},
    )
    yield case(
        "gcloud absent",
        real + ["--phase", "candidate"],
        env={"PATH": "{root}/bin:" + path_without("gcloud")},
        setup=setup_factory(gcloud=False),
    )
    yield case(
        "all, candidate URL smoked, promoted",
        real + ["--smoke-path", "/health"],
        env={"FAKE_STABLE": "rev-old", "FAKE_SERVICE_URL": "https://live.example"},
        setup=setup_factory(json=JSON_CAND),
    )
    yield case(
        "all, --refresh, candidate URL smoked",
        real + ["--refresh"],
        env={"FAKE_STABLE": "rev-old", "FAKE_SERVICE_URL": "https://live.example"},
        setup=setup_factory(json=JSON_CAND),
    )
    yield case(
        "all, smoke curl fails",
        real,
        env={
            "FAKE_STABLE": "rev-old",
            "FAKE_SERVICE_URL": "https://live.example",
            "FAKE_CURL_RC": "22",
        },
        setup=setup_factory(json=JSON_CAND),
    )
    yield case(
        "all, curl absent",
        real,
        env={
            "FAKE_STABLE": "rev-old",
            "FAKE_SERVICE_URL": "https://live.example",
            "PATH": "{root}/bin:" + path_without("curl"),
        },
        setup=setup_factory(json=JSON_CAND, curl=False),
    )
    yield case(
        "all, custom smoke inline",
        real
        + [
            "--custom-smoke-script",
            'echo "inline smoke $CAND"; echo "promote=$TABULA_PROMOTE" >&2',
        ],
        env={"FAKE_STABLE": "rev-old", "FAKE_SERVICE_URL": "https://live.example"},
        setup=setup_factory(json=JSON_CAND),
    )
    yield case(
        "all, custom smoke file",
        real + ["--custom-smoke-script-file", "smoke/check.sh"],
        env={"FAKE_STABLE": "rev-old", "FAKE_SERVICE_URL": "https://live.example"},
        setup=setup_factory(json=JSON_CAND),
    )
    yield case(
        "all, custom smoke fails",
        real + ["--custom-smoke-script-file", "smoke/check.sh"],
        env={
            "FAKE_STABLE": "rev-old",
            "FAKE_SERVICE_URL": "https://live.example",
            "FAKE_SMOKE_RC": "7",
        },
        setup=setup_factory(json=JSON_CAND),
    )
    yield case(
        "smoke, non-first deploy with no candidate tag fails (#808)",
        real + ["--phase", "smoke"],
        env={"FAKE_STABLE": "rev-old", "FAKE_SERVICE_URL": "https://live.example"},
        setup=setup_factory(json='{"status":{"traffic":[{"revisionName":"rev-old"}]}}'),
    )
    yield case(
        "smoke, first deploy smokes the live URL",
        real + ["--phase", "smoke", "--smoke-path", "/healthz"],
        env={"FAKE_SERVICE_URL": "https://live.example"},
    )
    yield case(
        "smoke, no service URL skips",
        real + ["--phase", "smoke"],
        env={"FAKE_STABLE": "rev-old"},
    )
    yield case(
        "all, null service URL skips smoke and promote",
        real,
        env={"FAKE_SERVICE_URL": "null"},
    )
    yield case(
        "all, service URL output fails",
        real,
        env={"FAKE_SERVICE_URL": "https://live.example", "FAKE_OUTPUT_RC": "1"},
    )
    yield case(
        "candidate up fails",
        real,
        env={"FAKE_STABLE": "rev-old", "FAKE_UP_FAIL": "false"},
    )
    yield case(
        "promote up fails",
        real,
        env={
            "FAKE_STABLE": "rev-old",
            "FAKE_SERVICE_URL": "https://live.example",
            "FAKE_UP_FAIL": "true",
        },
        setup=setup_factory(json=JSON_CAND),
    )
    yield case(
        "invalid JSON from gcloud, first deploy",
        real + ["--phase", "smoke"],
        env={"FAKE_SERVICE_URL": "https://live.example"},
        setup=setup_factory(json="{not json"),
    )
    yield case(
        "candidate with null url",
        real + ["--phase", "smoke"],
        env={"FAKE_STABLE": "rev-old", "FAKE_SERVICE_URL": "https://live.example"},
        setup=setup_factory(
            json='{"status":{"traffic":[{"tag":"candidate","url":null}]}}'
        ),
    )
    yield case(
        "two JSON documents, two candidates: the first wins",
        real + ["--phase", "smoke"],
        env={"FAKE_STABLE": "rev-old"},
        setup=setup_factory(
            json='{"status":{"traffic":[{"tag":"candidate","url":"https://a"}]}}\n'
            '{"status":{"traffic":[{"tag":"candidate","url":"https://b"}]}}'
        ),
    )
    yield case(
        "non-object traffic entry stops the filter",
        real + ["--phase", "smoke"],
        env={"FAKE_STABLE": "rev-old", "FAKE_SERVICE_URL": "https://live.example"},
        setup=setup_factory(
            json='{"status":{"traffic":[7,{"tag":"candidate","url":"https://a"}]}}'
        ),
    )
    yield case(
        "numeric candidate url",
        real + ["--phase", "smoke"],
        env={"FAKE_STABLE": "rev-old"},
        setup=setup_factory(
            json='{"status":{"traffic":[{"tag":"candidate","url":42}]}}'
        ),
    )
    yield case(
        "pulumi-cmd.sh missing from the workspace",
        real,
        env={"FAKE_STABLE": "rev-old"},
        setup=setup_factory(pulumi_cmd=False),
    )
    yield case(
        "stdin is passed through to gcloud",
        real + ["--phase", "promote"],
        env={"FAKE_STABLE": "rev-x"},
        stdin=b"ignored\n",
    )


JQ = ""


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
    global JQ
    JQ = find_jq()
    h = Harness(
        "cloud-run parity",
        need_env("CLOUD_RUN_SH"),
        need_env("CLOUD_RUN_RS"),
    )
    for c in cases():
        h.check(c)
    return h.finish()


if __name__ == "__main__":
    sys.exit(main())
