#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Hermetic test for the Rust pipeline-mouse-daemon.  Stubs gh,
# GRAVASTAR_BIN, and PIPELINE_CMD so every LED state, the transition /
# steady distinction, and SIGINT/SIGTERM cleanup are exercised without
# network or hardware.
set -uo pipefail

BIN="${1:?need path to pipeline-mouse-daemon binary}"
[[ "$BIN" = /* ]] || BIN="$(pwd)/$BIN"

fails=0
test_ok()  { echo "  ok - $1"; }
test_bad() { echo "  NOT OK - $1" >&2; fails=$((fails + 1)); }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ── Mock binaries ────────────────────────────────────────────────────

MOCK_BIN="${WORK}/bin"
mkdir -p "$MOCK_BIN"

# Mock gh: returns a deterministic SHA for commit resolution
cat > "${MOCK_BIN}/gh" << 'EOF'
#!/usr/bin/env bash
case "$*" in
  *repos/*/commits/*) echo "abc12345def67890abc12345def67890abc12345" ;;
  *) echo '{}' ;;
esac
EOF
chmod +x "${MOCK_BIN}/gh"

# Mock date: deterministic timestamps
cat > "${MOCK_BIN}/date" << 'EOF'
#!/usr/bin/env bash
echo "12:34:56"
EOF
chmod +x "${MOCK_BIN}/date"

# Mock gravastar-mouse: records every invocation
GRAVASTAR_LOG="${WORK}/gravastar-calls.log"
cat > "${WORK}/gravastar-mouse" << SCRIPT
#!/usr/bin/env bash
echo "\$@" >> "${GRAVASTAR_LOG}"
SCRIPT
chmod +x "${WORK}/gravastar-mouse"

PIPELINE_SCRIPT="${WORK}/pipeline-cmd.sh"

# ── Helpers ──────────────────────────────────────────────────────────

setup_pipeline() {
  local rc=$1; shift
  local output="$*"
  cat > "$PIPELINE_SCRIPT" << EOFSCRIPT
#!/usr/bin/env bash
echo "Checking pipeline..."
echo "${output}"
exit ${rc}
EOFSCRIPT
  chmod +x "$PIPELINE_SCRIPT"
}

run_once() {
  > "$GRAVASTAR_LOG"
  GRAVASTAR_BIN="${WORK}/gravastar-mouse" \
  PIPELINE_CMD="$PIPELINE_SCRIPT" \
  PIPELINE_REPO="test/repo" \
  PIPELINE_BRANCH="main" \
  POLL_INTERVAL=1 \
  MOUSE_DAEMON_ONCE=1 \
  PATH="${MOCK_BIN}:${PATH}" \
    "$BIN" 2>&1
}

# ── Test 1: solid_green ──────────────────────────────────────────────

setup_pipeline 0 "ALL_PASSED: 2 passed out of 2 total"
out=$(run_once)
call=$(cat "$GRAVASTAR_LOG" 2>/dev/null)
[[ "$call" == "signal success" ]] \
  && test_ok "solid_green: gravastar call" \
  || test_bad "solid_green: expected 'signal success', got '$call'"
echo "$out" | grep -q "solid_green" \
  && test_ok "solid_green: output mentions signal" \
  || test_bad "solid_green: output missing signal name"
echo "$out" | grep -q "Status transition" \
  && test_ok "solid_green: shows transition" \
  || test_bad "solid_green: missing transition"

# ── Test 2: solid_red ────────────────────────────────────────────────

setup_pipeline 1 "FAILED: 2 failed, 0 in-flight, 0 passed out of 2 total"
out=$(run_once)
call=$(cat "$GRAVASTAR_LOG" 2>/dev/null)
[[ "$call" == "color red --brightness 7" ]] \
  && test_ok "solid_red: gravastar call" \
  || test_bad "solid_red: expected 'color red --brightness 7', got '$call'"
echo "$out" | grep -q "solid_red" \
  && test_ok "solid_red: output mentions signal" \
  || test_bad "solid_red: output missing signal name"

# ── Test 3: pulsing_red ─────────────────────────────────────────────

setup_pipeline 1 "FAILED: 1 failed, 1 in-flight, 0 passed out of 2 total"
out=$(run_once)
call=$(cat "$GRAVASTAR_LOG" 2>/dev/null)
[[ "$call" == "breathe red --speed 7 --brightness 9" ]] \
  && test_ok "pulsing_red: gravastar call" \
  || test_bad "pulsing_red: expected 'breathe red --speed 7 --brightness 9', got '$call'"
echo "$out" | grep -q "pulsing_red" \
  && test_ok "pulsing_red: output mentions signal" \
  || test_bad "pulsing_red: output missing signal name"

# ── Test 4: pulsing_yellow ───────────────────────────────────────────

setup_pipeline 2 "IN_PROGRESS: 1 in-flight, 1 passed out of 2 total"
out=$(run_once)
call=$(cat "$GRAVASTAR_LOG" 2>/dev/null)
[[ "$call" == "breathe yellow --speed 5 --brightness 7" ]] \
  && test_ok "pulsing_yellow: gravastar call" \
  || test_bad "pulsing_yellow: expected 'breathe yellow --speed 5 --brightness 7', got '$call'"
echo "$out" | grep -q "pulsing_yellow" \
  && test_ok "pulsing_yellow: output mentions signal" \
  || test_bad "pulsing_yellow: output missing signal name"

# ── Test 5: warning ──────────────────────────────────────────────────

setup_pipeline 3 "No workflow runs found"
out=$(run_once)
call=$(cat "$GRAVASTAR_LOG" 2>/dev/null)
[[ "$call" == "signal warning" ]] \
  && test_ok "warning: gravastar call" \
  || test_bad "warning: expected 'signal warning', got '$call'"
echo "$out" | grep -q "warning" \
  && test_ok "warning: output mentions signal" \
  || test_bad "warning: output missing signal name"

# ── Test 6: steady state (same signal twice) ─────────────────────────

setup_pipeline 0 "ALL_PASSED: 2 passed out of 2 total"
> "$GRAVASTAR_LOG"
out=$(
  GRAVASTAR_BIN="${WORK}/gravastar-mouse" \
  PIPELINE_CMD="$PIPELINE_SCRIPT" \
  PIPELINE_REPO="test/repo" \
  PIPELINE_BRANCH="main" \
  POLL_INTERVAL=0 \
  MAX_ITERATIONS=2 \
  PATH="${MOCK_BIN}:${PATH}" \
    "$BIN" 2>&1
)
echo "$out" | grep -q "Status transition" \
  && test_ok "steady: first iteration is transition" \
  || test_bad "steady: first iteration not transition"
echo "$out" | grep -q "Status steady" \
  && test_ok "steady: second iteration is steady" \
  || test_bad "steady: second iteration not steady"
line_count=$(wc -l < "$GRAVASTAR_LOG" | tr -d ' ')
[[ "$line_count" -eq 1 ]] \
  && test_ok "steady: gravastar called once (transition only)" \
  || test_bad "steady: gravastar called $line_count times (expected 1)"

# ── Test 7: SIGTERM cleanup ──────────────────────────────────────────

setup_pipeline 0 "ALL_PASSED: 2 passed out of 2 total"
> "$GRAVASTAR_LOG"

GRAVASTAR_BIN="${WORK}/gravastar-mouse" \
PIPELINE_CMD="$PIPELINE_SCRIPT" \
PIPELINE_REPO="test/repo" \
PIPELINE_BRANCH="main" \
POLL_INTERVAL=60 \
MAX_ITERATIONS=1000 \
PATH="${MOCK_BIN}:${PATH}" \
  "$BIN" > "${WORK}/sigterm_out.txt" 2>&1 &
DAEMON_PID=$!

sleep 1
kill -TERM "$DAEMON_PID" 2>/dev/null
wait "$DAEMON_PID" 2>/dev/null
rc=$?

[[ "$rc" -eq 0 ]] \
  && test_ok "SIGTERM: exit code 0" \
  || test_bad "SIGTERM: exit code $rc"
grep -q "Stopping daemon" "${WORK}/sigterm_out.txt" \
  && test_ok "SIGTERM: cleanup message" \
  || test_bad "SIGTERM: cleanup message missing"
grep -q "restore" "$GRAVASTAR_LOG" \
  && test_ok "SIGTERM: restore called" \
  || test_bad "SIGTERM: restore not called"

# ── Test 8: Internal polling (no PIPELINE_CMD, direct gh api actions/runs) ──

cat > "${MOCK_BIN}/gh" << 'EOF'
#!/usr/bin/env bash
case "$*" in
  *repos/*/commits/*) echo "abc12345def67890abc12345def67890abc12345" ;;
  *actions/runs*) echo '{"total_count":2,"workflow_runs":[{"name":"CI","status":"completed","conclusion":"failure"},{"name":"delivery","status":"in_progress","conclusion":null}]}' ;;
  *) echo '{}' ;;
esac
EOF
chmod +x "${MOCK_BIN}/gh"

> "$GRAVASTAR_LOG"
out=$(
  GRAVASTAR_BIN="${WORK}/gravastar-mouse" \
  PIPELINE_REPO="test/repo" \
  PIPELINE_BRANCH="main" \
  POLL_INTERVAL=1 \
  MOUSE_DAEMON_ONCE=1 \
  PATH="${MOCK_BIN}:${PATH}" \
    "$BIN" 2>&1
)
call=$(cat "$GRAVASTAR_LOG" 2>/dev/null)
[[ "$call" == "breathe red --speed 7 --brightness 9" ]] \
  && test_ok "internal poll: gravastar call (pulsing_red)" \
  || test_bad "internal poll: expected 'breathe red --speed 7 --brightness 9', got '$call'"
echo "$out" | grep -q "FAILED: 1 failed, 1 in-flight" \
  && test_ok "internal poll: summary line matches pipeline-status" \
  || test_bad "internal poll: summary line mismatch: $out"

# ── Results ──────────────────────────────────────────────────────────

if [[ "$fails" -eq 0 ]]; then
  echo "PASS (all pipeline-mouse-daemon tests passed)"
  exit 0
else
  echo "FAIL ($fails test(s) failed)"
  exit 1
fi
