#!/usr/bin/env bash
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

# Hermetic guard for tabula-deploy-preflight.sh. The property that matters is
# the fail-open invariant: `unchanged=true` ONLY on a confident match; every
# error path deploys. A regression here that made it fail CLOSED would skip a
# real deploy — an outage-class bug — so each error path is pinned.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${1:-${HERE}/tabula-deploy-preflight.sh}"
[[ "$SCRIPT" == /* ]] || SCRIPT="$PWD/$SCRIPT"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/app"
: > "$work/app/Pulumi.development.yaml"

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }

# fake gcloud: serves status.traffic and honours --format the way gcloud does,
# so the old `value(status.traffic[0].revisionName)` read and the JSON read
# both see the same service. $FAKE_TRAFFIC is the raw traffic array; without
# it, $FAKE_LIVE (if set) is a single revision at 100%. Also simulates the
# exit-0 reauth error and a non-zero exit.
cat > "$work/fake-gcloud" <<'EOF'
#!/usr/bin/env bash
if [ "${FAKE_GCLOUD_AUTHFAIL:-0}" = "1" ]; then
  echo "ERROR: (gcloud.run.services.describe) Reauthentication failed." >&2
  exit 0
fi
if [ "${FAKE_GCLOUD_RC:-0}" != "0" ]; then
  echo "ERROR: boom" >&2; exit "${FAKE_GCLOUD_RC}"
fi
fmt=""
for a in "$@"; do case "$a" in --format=*) fmt="${a#--format=}" ;; esac; done
FAKE_FORMAT="$fmt" python3 -I -c '
import json, os
live = os.environ.get("FAKE_LIVE", "")
traffic = os.environ.get("FAKE_TRAFFIC", "")
traffic = json.loads(traffic) if traffic else ([{"revisionName": live, "percent": 100}] if live else [])
fmt = os.environ["FAKE_FORMAT"]
if fmt == "json":
    print(json.dumps({"metadata": {"name": "svc"}, "status": {"traffic": traffic}}, indent=2))
elif fmt == "value(status.traffic[0].revisionName)":
    print(traffic[0].get("revisionName", "") if traffic else "")
else:
    raise SystemExit("fake-gcloud: unsupported --format=" + fmt)
'
EOF
chmod +x "$work/fake-gcloud"

# fake revname: prints $FAKE_DESIRED, or fails when FAKE_REVNAME_RC set.
cat > "$work/fake-revname" <<'EOF'
#!/usr/bin/env bash
if [ "${FAKE_REVNAME_RC:-0}" != "0" ]; then echo "revname: boom" >&2; exit "${FAKE_REVNAME_RC}"; fi
printf '%s\n' "${FAKE_DESIRED:-}"
EOF
chmod +x "$work/fake-revname"

run() { # prints the unchanged= value written to GITHUB_OUTPUT
  local out="$work/out"; : > "$out"
  if [[ "$SCRIPT" == *.sh ]]; then
    GITHUB_OUTPUT="$out" \
    DEPLOY_ENV=development GCP_PROJECT_ID=prj-d GCP_REGION=us-central1 \
    SERVICE_NAME=tabula-api IMAGE_DIGEST="img@sha256:deadbeef12" \
    PULUMI_DIR="$work/app" CONFIG_FILE=Pulumi.development.yaml \
    GCLOUD_BIN="$work/fake-gcloud" REVNAME="$work/fake-revname" \
    FAKE_DESIRED="${FAKE_DESIRED:-}" FAKE_LIVE="${FAKE_LIVE:-}" FAKE_TRAFFIC="${FAKE_TRAFFIC:-}" \
    FAKE_GCLOUD_RC="${FAKE_GCLOUD_RC:-0}" FAKE_GCLOUD_AUTHFAIL="${FAKE_GCLOUD_AUTHFAIL:-0}" \
    FAKE_REVNAME_RC="${FAKE_REVNAME_RC:-0}" \
      bash "$SCRIPT" >/dev/null 2>&1
  else
    GITHUB_OUTPUT="$out" \
    DEPLOY_ENV=development GCP_PROJECT_ID=prj-d GCP_REGION=us-central1 \
    SERVICE_NAME=tabula-api IMAGE_DIGEST="img@sha256:deadbeef12" \
    PULUMI_DIR="$work/app" CONFIG_FILE=Pulumi.development.yaml \
    GCLOUD_BIN="$work/fake-gcloud" REVNAME="$work/fake-revname" \
    FAKE_DESIRED="${FAKE_DESIRED:-}" FAKE_LIVE="${FAKE_LIVE:-}" FAKE_TRAFFIC="${FAKE_TRAFFIC:-}" \
    FAKE_GCLOUD_RC="${FAKE_GCLOUD_RC:-0}" FAKE_GCLOUD_AUTHFAIL="${FAKE_GCLOUD_AUTHFAIL:-0}" \
    FAKE_REVNAME_RC="${FAKE_REVNAME_RC:-0}" \
      "$SCRIPT" >/dev/null 2>&1
  fi
  sed -n 's/^unchanged=//p' "$out"
}

expect() { # <label> <want>
  local got; got="$(run)"
  if [ "$got" = "$2" ]; then pass "$1 (unchanged=$got)"; else fail "$1 — got '$got', want '$2'"; fi
}

echo "the ONE skip case: desired == live"
FAKE_DESIRED="tabula-api-development-de662165-1b062f" FAKE_LIVE="tabula-api-development-de662165-1b062f" expect "matching names skip" true

echo "every other path must DEPLOY (fail open):"
FAKE_DESIRED="tabula-api-development-aaaa1111-bbbbbb" FAKE_LIVE="tabula-api-development-de662165-1b062f" expect "different names deploy" false
FAKE_DESIRED="tabula-api-development-de662165-1b062f" FAKE_LIVE="" expect "empty live (first deploy) deploys" false
FAKE_DESIRED="" FAKE_LIVE="x" FAKE_REVNAME_RC=1 expect "revname failure deploys" false
FAKE_DESIRED="x" FAKE_LIVE="x" FAKE_GCLOUD_RC=1 expect "gcloud non-zero deploys" false
FAKE_DESIRED="x" FAKE_GCLOUD_AUTHFAIL=1 expect "gcloud exit-0 reauth error deploys" false

echo "the skip must not fire when a single field differs"
FAKE_DESIRED="tabula-api-development-de662165-1b062f" FAKE_LIVE="tabula-api-development-de662165-999999" expect "different config hash deploys" false

echo "live is the revision carrying traffic, not the first traffic entry"
# A failed candidate at 0% behind the candidate tag, listed first, has the
# desired name (same digest + config). It is not live: skipping would leave
# the old revision serving and report the deploy green.
FAKE_DESIRED="tabula-api-development-de662165-1b062f" \
  FAKE_TRAFFIC='[{"tag":"candidate","revisionName":"tabula-api-development-de662165-1b062f","url":"https://c"},{"revisionName":"tabula-api-development-aaaa1111-bbbbbb","percent":100}]' \
  expect "failed 0% candidate listed first deploys" false
FAKE_DESIRED="tabula-api-development-de662165-1b062f" \
  FAKE_TRAFFIC='[{"tag":"candidate","revisionName":"tabula-api-development-aaaa1111-bbbbbb","percent":0},{"revisionName":"tabula-api-development-de662165-1b062f","percent":100}]' \
  expect "desired serving 100% behind a 0% entry skips" true
FAKE_DESIRED="x" FAKE_TRAFFIC='[{"tag":"candidate","revisionName":"x","percent":0}]' expect "nothing carrying traffic deploys" false

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails" >&2; exit 1; fi
echo "ALL PASS"
