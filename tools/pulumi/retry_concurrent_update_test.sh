#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Tests for retry-concurrent-update.sh on its own: what the wrapper tests
# (pulumi_cmd_test.sh) cannot see because they run with a zero delay -- the
# capped backoff -- plus stdout/stderr pass-through and the exact match. A stub
# command plays pulumi and a stub `sleep` records every wait instead of waiting.
set -uo pipefail

RETRY="${1:?usage: retry_concurrent_update_test.sh <path to retry-concurrent-update.sh>}"
RETRY="$(cd "$(dirname "$RETRY")" && pwd)/$(basename "$RETRY")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass_n=0
fail_n=0
pass() { echo "  ✓ $1"; pass_n=$((pass_n + 1)); }
fail() { echo "  ✗ $1" >&2; fail_n=$((fail_n + 1)); }

CONFLICT="error: [409] Conflict: You have a running update for the stack 'tabula-deploy-identity/development'. Your organization does not support concurrent updates."

stubs="$work/stubs"
mkdir -p "$stubs"
# fake-pulumi: fails STUB_FAIL_TIMES times with STUB_MSG on stderr, then exits 0.
cat >"$stubs/fake-pulumi" <<'EOF'
#!/usr/bin/env bash
n=0
[ -f "$STUB_COUNT" ] && n="$(cat "$STUB_COUNT")"
n=$((n + 1))
echo "$n" >"$STUB_COUNT"
echo "stdout from attempt $n"
if [ "$n" -le "${STUB_FAIL_TIMES:-0}" ]; then
  echo "$STUB_MSG" >&2
  exit 23
fi
exit 0
EOF
cat >"$stubs/sleep" <<'EOF'
#!/usr/bin/env bash
echo "$1" >>"$SLEEP_LOG"
EOF
chmod +x "$stubs/fake-pulumi" "$stubs/sleep"

# run <fail_times> <msg> [env...] -> "<rc> <invocations> <waits>"; stdout in $work/out
run() {
  local times="$1" msg="$2"
  shift 2
  : >"$work/count"
  : >"$work/sleeps"
  env PATH="$stubs:/usr/bin:/bin" STUB_COUNT="$work/count" SLEEP_LOG="$work/sleeps" \
    STUB_FAIL_TIMES="$times" STUB_MSG="$msg" "$@" \
    bash "$RETRY" fake-pulumi up --yes >"$work/out" 2>"$work/err"
  local rc=$?
  echo "$rc $(cat "$work/count") $(tr '\n' ',' <"$work/sleeps")"
}

echo "--- the concurrent-update 409 is retried, then succeeds ---"
read -r rc n waits <<<"$(run 2 "$CONFLICT")"
if [ "$rc" -eq 0 ] && [ "$n" -eq 3 ]; then pass "retried twice, succeeded on attempt 3"; else
  fail "wanted rc=0 n=3, got rc=$rc n=$n"; fi
if grep -q "stdout from attempt 3" "$work/out"; then pass "the command's stdout passes through unchanged"; else
  fail "stdout was not passed through"; fi
if grep -qF "$CONFLICT" "$work/err"; then pass "the 409 itself is still shown on stderr"; else
  fail "stderr was swallowed"; fi

echo "--- the wait doubles and is capped ---"
read -r rc n waits <<<"$(run 6 "$CONFLICT" PULUMI_CONFLICT_RETRY_DELAY=15 PULUMI_CONFLICT_MAX_DELAY=60)"
if [ "$waits" = "15,30,60,60,60,60," ] && [ "$rc" -eq 0 ]; then pass "waits 15,30,60,60,60,60 (capped at 60)"; else
  fail "wanted waits 15,30,60,60,60,60 and rc=0, got '$waits' rc=$rc"; fi

echo "--- the default budget ---"
read -r rc n waits <<<"$(run 99 "$CONFLICT")"
if [ "$rc" -eq 23 ] && [ "$n" -eq 8 ] && [ "$waits" = "15,30,60,60,60,60,60," ]; then
  pass "8 attempts, ~6 minutes of waiting, then the command's own exit code"
else
  fail "wanted rc=23 n=8 waits=15,30,60,60,60,60,60, got rc=$rc n=$n waits='$waits'"
fi
if grep -q "giving up" "$work/err"; then pass "says it gave up"; else fail "no give-up message"; fi

echo "--- anything else fails at once ---"
read -r rc n waits <<<"$(run 99 "error: provider mis-configured")"
if [ "$rc" -eq 23 ] && [ "$n" -eq 1 ] && [ -z "$waits" ]; then pass "an unrelated error is not retried"; else
  fail "wanted rc=23 n=1 no waits, got rc=$rc n=$n waits='$waits'"; fi
read -r rc n waits <<<"$(run 99 "error: [409] Conflict: Another update is currently in progress.")"
if [ "$rc" -eq 23 ] && [ "$n" -eq 1 ]; then pass "a 409 without the concurrent-update marker is not retried"; else
  fail "wanted rc=23 n=1, got rc=$rc n=$n"; fi
read -r rc n waits <<<"$(run 99 "warning: this stack does not support concurrent updates")"
if [ "$rc" -eq 23 ] && [ "$n" -eq 1 ]; then pass "the marker without a 409 is not retried"; else
  fail "wanted rc=23 n=1, got rc=$rc n=$n"; fi

echo
if [ "$fail_n" -gt 0 ]; then
  echo "FAILED: $fail_n"
  exit 1
fi
echo "ALL PASS ($pass_n)"
