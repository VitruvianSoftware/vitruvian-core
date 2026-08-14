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

# Unit tests for tools/ci/foundation-app-digest-guard.sh's pure
# missing_digest_apps() function. Sourced, not executed -- no GITHUB_ENV, no
# real Pulumi.production.yaml needed.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/foundation-app-digest-guard.sh"

fails=0
ok() { printf '  ok - %s\n' "$1"; }
bad() { printf '  NOT OK - %s\n' "$1" >&2; fails=$((fails + 1)); }

# shellcheck source=/dev/null
source "$SCRIPT"   # source-safe: main() runs only when executed, not sourced
set +e -u -o pipefail

pulumi_file='
config:
  gcp-app-infra:oauth-user-inspector_workload_enabled: "true"
  gcp-app-infra:zitadel-apps_workload_enabled: "false"
  gcp-app-infra:mcp-slack_workload_enabled: "true"
'

got="$(missing_digest_apps "$pulumi_file" "oauth-user-inspector=sha256:aaa,mcp-slack=sha256:bbb")"
[ "$got" = "" ] && ok "every enabled workload has a digest -> no missing apps" \
  || bad "expected no missing apps (got '$got')"

got="$(missing_digest_apps "$pulumi_file" "oauth-user-inspector=sha256:aaa")"
[ "$got" = "mcp-slack" ] && ok "one enabled workload missing its digest is reported" \
  || bad "expected 'mcp-slack' missing (got '$got')"

got="$(missing_digest_apps "$pulumi_file" "")"
[ "$got" = "oauth-user-inspector mcp-slack" ] && ok "no digests supplied at all reports every enabled workload" \
  || bad "expected both enabled apps missing (got '$got')"

got="$(missing_digest_apps "$pulumi_file" "mcp-slack=sha256:bbb,zitadel-apps=sha256:ccc")"
[ "$got" = "oauth-user-inspector" ] && ok "a digest for a DISABLED workload doesn't excuse an enabled one" \
  || bad "expected 'oauth-user-inspector' missing (got '$got')"

got="$(missing_digest_apps '
config:
  gcp-app-infra:zitadel-apps_workload_enabled: "false"
' "")"
[ "$got" = "" ] && ok "no workloads enabled at all -> nothing missing" \
  || bad "expected no missing apps (got '$got')"

got="$(missing_digest_apps "$pulumi_file" "oauth-user-inspector=sha256:aaa,mcp-slack=sha256:bbb,unrelated-app=sha256:zzz")"
[ "$got" = "" ] && ok "an extra digest for an app not in the file is harmless" \
  || bad "expected no missing apps (got '$got')"

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails" >&2; exit 1; fi
echo "ALL PASS"
