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

# Unit tests for tools/ci/gcp-secret-or-fail.sh's pure secret_or_fail()
# decision function. Sourced, not executed with gcloud -- hermetic, no
# network, no credentials.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/gcp-secret-or-fail.sh"

fails=0
ok() { printf '  ok - %s\n' "$1"; }
bad() { printf '  NOT OK - %s\n' "$1" >&2; fails=$((fails + 1)); }

# shellcheck source=/dev/null
source "$SCRIPT"   # source-safe: main() runs only when executed, not sourced
# Sourcing imported the script's `set -euo pipefail`; clear the inherited -e
# so the failure cases below (which intentionally return 1) don't abort here.
set +e -u -o pipefail

got="$(secret_or_fail 0 "sekrit-value" "" "DATABASE_URL" "prj-x" "some context")"
[ "$got" = "sekrit-value" ] && ok "rc=0 with a value returns it" \
  || bad "clean fetch should return the value (got '$got')"

if secret_or_fail 0 "" "" "DATABASE_URL" "prj-x" "" >/dev/null 2>&1; then
  bad "rc=0 with an EMPTY value must fail (never hand back an empty secret)"
else
  ok "rc=0 with an empty value fails closed"
fi

if secret_or_fail 1 "" "ERROR: (gcloud.secrets.versions.access) PERMISSION_DENIED: caller lacks permission" "CLOUDFLARE_API_TOKEN" "prj-y" "deploy SA needs secretAccessor" >/dev/null 2>&1; then
  bad "a nonzero rc must fail, regardless of stderr content"
else
  ok "nonzero rc fails closed"
fi

err="$(secret_or_fail 1 "" "ERROR: PERMISSION_DENIED" "CLOUDFLARE_API_TOKEN" "prj-y" "deploy SA needs secretAccessor" 2>&1 >/dev/null)"
echo "$err" | grep -q "CLOUDFLARE_API_TOKEN" && echo "$err" | grep -q "prj-y" && echo "$err" | grep -q "deploy SA needs secretAccessor" \
  && ok "error message names the secret id, project, AND the caller's context" \
  || bad "error message missing expected detail:\n$err"

err="$(secret_or_fail 1 "" "ERROR: PERMISSION_DENIED: caller lacks permission" "X" "prj-x" "" 2>&1 >/dev/null)"
echo "$err" | grep -q "PERMISSION_DENIED" \
  && ok "raw gcloud stderr is surfaced so a wrong secret id isn't mistaken for an IAM gap" \
  || bad "raw gcloud stderr should be surfaced:\n$err"

if secret_or_fail 0 "value-with-trailing-noise" "some warning printed to stderr despite rc=0" "X" "prj-x" "" >/dev/null 2>&1; then
  ok "rc=0 always wins regardless of stderr content (matches gcloud's own success signal)"
else
  bad "rc=0 should not fail even if stderr has content"
fi

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails" >&2; exit 1; fi
echo "ALL PASS"
