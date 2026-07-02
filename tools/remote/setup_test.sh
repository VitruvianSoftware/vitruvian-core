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

# setup_test.sh — regression tests for tools/remote/setup.sh's user.bazelrc
# output. Exists because of a real bug: header lines written under BOTH
# common:remote and common:remotecache scopes COMMA-JOINED into "KEY,KEY"
# when a dev ran the documented `--config=remote` on a machine with the
# remotecache local default (--remote_header repeats are joined, not deduped).
# The invariant under test: across every scope, the auth header expands
# EXACTLY ONCE for any config combination.
set -euo pipefail

SETUP="$(pwd)/tools/remote/setup.sh"
[ -f "$SETUP" ] || SETUP="$(dirname "$0")/setup.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }

run_setup() { # $@ extra args; runs in $WS
  BUILD_WORKSPACE_DIRECTORY="$WS" bash "$SETUP" \
    --cache buildbuddy --provider buildbuddy --key TESTKEY --no-ci --yes "$@" \
    >/dev/null 2>&1
}

# header_expansions: total header lines that could apply to ANY invocation --
# unscoped `common` + any config-scoped variant. The doubling bug shows up as
# a count >1 here (one line per scope that can co-expand).
header_expansions() {
  grep -cE -- '^common(:[a-z-]+)? --remote_header=x-buildbuddy-api-key=' "$WS/user.bazelrc" || true
}

# --- T1: fresh setup -> exactly one UNSCOPED header line -------------------
WS="$(mktemp -d)"; cd "$WS"; git init -q -b main . 2>/dev/null || true
run_setup
[ "$(header_expansions)" = "1" ] || fail "expected exactly 1 remote_header expansion, got $(header_expansions)"
grep -q -- '^common --remote_header=x-buildbuddy-api-key=TESTKEY$' "$WS/user.bazelrc" \
  || fail "header line must be UNSCOPED (plain 'common')"
grep -q -- '^common --config=remotecache$' "$WS/user.bazelrc" \
  || fail "local default line missing"
echo "ok T1: single unscoped header + local default"

# --- T2: idempotent re-run (key rotation) -> still exactly one -------------
BUILD_WORKSPACE_DIRECTORY="$WS" bash "$SETUP" \
  --cache buildbuddy --provider buildbuddy --key ROTATED --no-ci --yes >/dev/null 2>&1
[ "$(header_expansions)" = "1" ] || fail "re-run duplicated header lines"
grep -q "ROTATED" "$WS/user.bazelrc" || fail "rotated key not written"
grep -q "TESTKEY" "$WS/user.bazelrc" && fail "old key survived rotation"
[ "$(grep -c '>>> build cache' "$WS/user.bazelrc")" = "1" ] || fail "managed block duplicated"
echo "ok T2: idempotent rotation"

# --- T3: legacy scoped headers are cleaned up on re-run --------------------
cat >> "$WS/user.bazelrc" <<'EOF'
common:remote --remote_header=x-buildbuddy-api-key=LEGACY
common:remotecache --remote_header=x-buildbuddy-api-key=LEGACY
EOF
run_setup
[ "$(header_expansions)" = "1" ] || fail "legacy scoped headers not cleaned (got $(header_expansions))"
echo "ok T3: legacy scoped headers cleaned"

# --- T4: --no-local-default omits the default, keeps the single header -----
run_setup --no-local-default
grep -q -- '^common --config=remotecache$' "$WS/user.bazelrc" \
  && fail "--no-local-default still wrote the default line"
[ "$(header_expansions)" = "1" ] || fail "no-local-default broke header count"
echo "ok T4: opt-out"

# --- T5: no-clobber guard leaves a committed remote.bazelrc untouched ------
mkdir -p "$WS/tools"
printf 'SENTINEL\ncommon:remote --remote_executor=grpcs://remote.buildbuddy.io\n' > "$WS/tools/remote.bazelrc"
run_setup
grep -q '^SENTINEL$' "$WS/tools/remote.bazelrc" || fail "setup clobbered a committed remote.bazelrc with the same endpoint"
echo "ok T5: no-clobber guard"

echo "PASS: setup_test.sh"
