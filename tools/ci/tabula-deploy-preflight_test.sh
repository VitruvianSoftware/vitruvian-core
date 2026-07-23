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
SCRIPT="${HERE}/tabula-deploy-preflight.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/app"
: > "$work/app/Pulumi.development.yaml"

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }

# fake gcloud: prints $FAKE_LIVE, or simulates the exit-0 reauth error.
cat > "$work/fake-gcloud" <<'EOF'
#!/usr/bin/env bash
if [ "${FAKE_GCLOUD_AUTHFAIL:-0}" = "1" ]; then
  echo "ERROR: (gcloud.run.services.describe) Reauthentication failed." >&2
  exit 0
fi
if [ "${FAKE_GCLOUD_RC:-0}" != "0" ]; then
  echo "ERROR: boom" >&2; exit "${FAKE_GCLOUD_RC}"
fi
printf '%s\n' "${FAKE_LIVE:-}"
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
  GITHUB_OUTPUT="$out" \
  DEPLOY_ENV=development GCP_PROJECT_ID=prj-d GCP_REGION=us-central1 \
  SERVICE_NAME=tabula-api IMAGE_DIGEST="img@sha256:deadbeef12" \
  PULUMI_DIR="$work/app" CONFIG_FILE=Pulumi.development.yaml \
  GCLOUD_BIN="$work/fake-gcloud" REVNAME="$work/fake-revname" \
  FAKE_DESIRED="${FAKE_DESIRED:-}" FAKE_LIVE="${FAKE_LIVE:-}" \
  FAKE_GCLOUD_RC="${FAKE_GCLOUD_RC:-0}" FAKE_GCLOUD_AUTHFAIL="${FAKE_GCLOUD_AUTHFAIL:-0}" \
  FAKE_REVNAME_RC="${FAKE_REVNAME_RC:-0}" \
    bash "$SCRIPT" >/dev/null 2>&1
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

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails" >&2; exit 1; fi
echo "ALL PASS"
