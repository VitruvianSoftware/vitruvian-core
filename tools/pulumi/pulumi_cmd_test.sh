#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Unit tests for pulumi_cmd.sh's concurrent-update (409) retry.
#
# Pulumi Cloud individual accounts serialize updates across the whole ACCOUNT,
# so an unrelated stack's update rejects this one with a 409. That is a queue,
# not a failure -- but retrying must be surgical: ONLY that error, ONLY for
# subcommands that take the update lock, and always bounded.
#
# Real failure this pins: oauth-user-inspector v1.11.0's PRODUCTION promotion
# (run 32355118334) died on a 409 raised by a concurrent tabula-web development
# update, leaving production on the previous revision.
set -uo pipefail

WRAPPER="${1:?usage: pulumi_cmd_test.sh <path to pulumi_cmd.sh>}"
WRAPPER="$(cd "$(dirname "$WRAPPER")" && pwd)/$(basename "$WRAPPER")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass_n=0
fail_n=0
pass() {
    echo "  ✓ $1"
    pass_n=$((pass_n + 1))
}
fail() {
    echo "  ✗ $1" >&2
    fail_n=$((fail_n + 1))
}

# A fake workspace: the wrapper cd's into $BUILD_WORKSPACE_DIRECTORY/$PROJECT_DIR
# and reads the identity map, so both must exist.
ws="$work/ws"
mkdir -p "$ws/tabula/infra/web" "$ws/tools/pulumi" "$ws/infrastructure"
: >"$ws/infrastructure/gcp-identities.tsv"
printf '#!/usr/bin/env bash\nexit 0\n' >"$ws/tools/pulumi/resolve_identity.sh"
chmod +x "$ws/tools/pulumi/resolve_identity.sh"

# `pulumi` stub: fails with $STUB_MSG for the first $STUB_FAILS invocations
# (tracked in a counter file), then succeeds. Records every invocation.
stubs="$work/stubs"
mkdir -p "$stubs"
cat >"$stubs/pulumi" <<'EOF'
#!/usr/bin/env bash
n=0
[ -f "$STUB_COUNT" ] && n="$(cat "$STUB_COUNT")"
n=$((n + 1))
echo "$n" >"$STUB_COUNT"
echo "invocation $n: $*" >>"$STUB_LOG"
if [ "$n" -le "${STUB_FAILS:-0}" ]; then
    echo "$STUB_MSG" >&2
    exit 255
fi
echo "pulumi stub: success on invocation $n"
exit 0
EOF
chmod +x "$stubs/pulumi"

CONFLICT_MSG="error: [409] Conflict: You have a running update for the stack 'pulumi_tabula_web/development'. Individual user accounts do not support concurrent updates."
OTHER_MSG="error: failed to register resource: rpc error: code = Unknown"

run_wrapper() { # <subcmd> <fails> <msg> ; echoes "<rc> <invocations>"
    local subcmd="$1" fails="$2" msg="$3"
    local count="$work/count.$RANDOM" log="$work/log.$RANDOM"
    : >"$count"
    : >"$log"
    env PATH="$stubs:/usr/bin:/bin" \
        BUILD_WORKSPACE_DIRECTORY="$ws" \
        STUB_COUNT="$count" STUB_LOG="$log" STUB_FAILS="$fails" STUB_MSG="$msg" \
        PULUMI_LOCK_BACKOFF_SECONDS=0 PULUMI_LOCK_MAX_ATTEMPTS=4 \
        bash "$WRAPPER" tabula/infra/web "$subcmd" --yes >/dev/null 2>&1
    local rc=$?
    echo "$rc $(cat "$count")"
}

echo "--- retries ONLY the concurrent-update 409 ---"
read -r rc n <<<"$(run_wrapper up 2 "$CONFLICT_MSG")"
if [ "$rc" -eq 0 ] && [ "$n" -eq 3 ]; then
    pass "a 409 that clears is retried until it succeeds (rc=$rc, invocations=$n)"
else
    fail "409 retry — got rc=$rc invocations=$n, want rc=0 invocations=3"
fi

read -r rc n <<<"$(run_wrapper up 1 "$OTHER_MSG")"
if [ "$rc" -ne 0 ] && [ "$n" -eq 1 ]; then
    pass "a NON-409 failure is never retried (rc=$rc, invocations=$n)"
else
    fail "non-409 must fail immediately — got rc=$rc invocations=$n, want rc!=0 invocations=1"
fi

echo "--- the retry is bounded ---"
read -r rc n <<<"$(run_wrapper up 99 "$CONFLICT_MSG")"
if [ "$rc" -ne 0 ] && [ "$n" -eq 4 ]; then
    pass "a permanent 409 stops at PULUMI_LOCK_MAX_ATTEMPTS (rc=$rc, invocations=$n)"
else
    fail "bounded retry — got rc=$rc invocations=$n, want rc!=0 invocations=4"
fi

echo "--- only lock-taking subcommands are wrapped ---"
read -r rc n <<<"$(run_wrapper preview 1 "$CONFLICT_MSG")"
if [ "$rc" -ne 0 ] && [ "$n" -eq 1 ]; then
    pass "a read-only subcommand is exec'd, not retried (rc=$rc, invocations=$n)"
else
    fail "preview must not retry — got rc=$rc invocations=$n, want rc!=0 invocations=1"
fi

echo "--- success is not disturbed ---"
read -r rc n <<<"$(run_wrapper up 0 "$CONFLICT_MSG")"
if [ "$rc" -eq 0 ] && [ "$n" -eq 1 ]; then
    pass "a clean up runs exactly once (rc=$rc, invocations=$n)"
else
    fail "clean up — got rc=$rc invocations=$n, want rc=0 invocations=1"
fi

echo
if [ "$fail_n" -gt 0 ]; then
    echo "FAILED: $fail_n"
    exit 1
fi
echo "ALL PASS ($pass_n)"
