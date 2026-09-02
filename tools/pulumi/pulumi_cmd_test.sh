#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Unit tests for pulumi-cmd.sh: verifying clean fail-fast execution and backend resolution.
set -uo pipefail

WRAPPER="${1:?usage: pulumi_cmd_test.sh <path to pulumi-cmd.sh>}"
WRAPPER="$(cd "$(dirname "$WRAPPER")" && pwd)/$(basename "$WRAPPER")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass_n=0
fail_n=0
pass() { echo "  ✓ $1"; pass_n=$((pass_n + 1)); }
fail() { echo "  ✗ $1" >&2; fail_n=$((fail_n + 1)); }

ws="$work/ws"
mkdir -p "$ws/tabula/infra/web" "$ws/tools/pulumi" "$ws/infrastructure"
: >"$ws/infrastructure/gcp-identities.tsv"
printf '#!/usr/bin/env bash\nexit 0\n' >"$ws/tools/pulumi/resolve_identity.sh"
chmod +x "$ws/tools/pulumi/resolve_identity.sh"

stubs="$work/stubs"
mkdir -p "$stubs"
cat >"$stubs/pulumi" <<'EOF'
#!/usr/bin/env bash
n=0
[ -f "$STUB_COUNT" ] && n="$(cat "$STUB_COUNT")"
n=$((n + 1))
echo "$n" >"$STUB_COUNT"
echo "invocation $n: backend=${PULUMI_BACKEND_URL:-unset} args=$*" >>"$STUB_LOG"
if [ "${STUB_FAIL:-0}" -eq 1 ]; then
    echo "simulated error: ${STUB_MSG:-failed}" >&2
    exit 23
fi
exit 0
EOF
chmod +x "$stubs/pulumi"

run_cmd() {
    local subcmd="$1" fail_flag="$2" msg="$3" backend_url="${4:-}" gcp_proj="${5:-}" pulumi_token="${6:-}"
    local count="$work/count.$RANDOM" log="$work/log.$RANDOM"
    : >"$count"
    : >"$log"
    env PATH="$stubs:/usr/bin:/bin" \
        BUILD_WORKSPACE_DIRECTORY="$ws" \
        STUB_COUNT="$count" STUB_LOG="$log" STUB_FAIL="$fail_flag" STUB_MSG="$msg" \
        PULUMI_BACKEND_URL="$backend_url" GOOGLE_CLOUD_PROJECT="$gcp_proj" \
        PULUMI_ACCESS_TOKEN="$pulumi_token" CI=1 \
        bash "$WRAPPER" tabula/infra/web "$subcmd" --stack development --yes >/dev/null 2>&1
    local rc=$?
    echo "$rc $(cat "$count") $(cat "$log")"
}

echo "--- 1. Clean execution passes immediately ---"
res="$(run_cmd up 0 "ok" "gs://bu2-tabula-pulumi-state-dev")"
read -r rc n _ <<<"$res"
if [ "$rc" -eq 0 ] && [ "$n" -eq 1 ]; then
    pass "clean pulumi up executes in exactly 1 invocation (rc=$rc, invocations=$n)"
else
    fail "clean pulumi up failed — rc=$rc, invocations=$n"
fi

echo "--- 2. Errors fail fast without retrying ---"
res="$(run_cmd up 1 "409 Conflict" "gs://bu2-tabula-pulumi-state-dev")"
read -r rc n _ <<<"$res"
if [ "$rc" -eq 23 ] && [ "$n" -eq 1 ]; then
    pass "error fails immediately with exit code 23 in 1 invocation (no retry loop)"
else
    fail "error fail-fast failed — rc=$rc, invocations=$n (wanted rc=23, n=1)"
fi

echo "--- 3. Backend URL and arguments passed faithfully ---"
res="$(run_cmd preview 0 "ok" "gs://my-custom-state-bucket")"
if echo "$res" | grep -q "backend=gs://my-custom-state-bucket" && echo "$res" | grep -q -- "--non-interactive"; then
    pass "PULUMI_BACKEND_URL and --non-interactive forwarded correctly"
else
    fail "argument or backend forwarding failed: $res"
fi

echo "--- 4. Dynamic GCS backend resolution from GCP Project ---"
res="$(run_cmd up 0 "ok" "" "prj-d-bu2-tabula-1234")"
if echo "$res" | grep -q "backend=gs://prj-d-bu2-tabula-1234-pulumi-state"; then
    pass "GCS state bucket derived dynamically from GOOGLE_CLOUD_PROJECT"
else
    fail "dynamic GCS state bucket derivation failed: $res"
fi

echo "--- 5. PULUMI_ACCESS_TOKEN wins over a derivable GCS bucket ---"
# THE PRODUCTION REGRESSION THIS GUARDS (2026-09-02): the deploy lanes export
# BOTH PULUMI_ACCESS_TOKEN and GCP_PROJECT_ID (_deploy-cloud-run.yaml:406,223).
# The wrapper derived gs://<proj>-pulumi-state from the project and preferred it,
# so every delivery deploy died with
#   "error listing stacks: could not list bucket: storage: bucket doesn't exist: 404"
# while the stacks actually lived on Pulumi Cloud. Token must take precedence.
res="$(run_cmd up 0 "ok" "" "prj-d-bu1-oss-floating-648a" "pul-fake-token")"
if echo "$res" | grep -q "backend=https://api.pulumi.com"; then
    pass "PULUMI_ACCESS_TOKEN takes precedence over GCS derivation (Pulumi Cloud)"
else
    fail "token did NOT win over GCS derivation — this is the 404 regression: $res"
fi

echo "--- 6. No token and no project falls back to Pulumi Cloud ---"
res="$(run_cmd up 0 "ok" "" "" "")"
if echo "$res" | grep -q "backend=https://api.pulumi.com"; then
    pass "defaults to Pulumi Cloud when neither token nor project is set"
else
    fail "default backend fallback failed: $res"
fi

echo "--- 7. Explicit PULUMI_BACKEND_URL still wins over everything ---"
res="$(run_cmd up 0 "ok" "gs://explicit-override" "prj-d-bu1-oss-floating-648a" "pul-fake-token")"
if echo "$res" | grep -q "backend=gs://explicit-override"; then
    pass "explicit PULUMI_BACKEND_URL overrides both token and project derivation"
else
    fail "explicit backend override regressed: $res"
fi


echo
if [ "$fail_n" -gt 0 ]; then
    echo "FAILED: $fail_n"
    exit 1
fi
echo "ALL PASS ($pass_n)"
