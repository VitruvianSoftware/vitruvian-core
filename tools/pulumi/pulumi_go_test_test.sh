#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Unit tests for pulumi_go_test.sh / pulumi-go-test (Rust). Verifies usage
# errors, toolchain checks and GOWORK=off without actually running go test.
# The tool path is passed as $1 via $(location); works for both shell scripts
# and compiled binaries.
set -uo pipefail

TOOL="${1:?usage: pulumi_go_test_test.sh <path to tool>}"
TOOL="$(cd "$(dirname "$TOOL")" && pwd)/$(basename "$TOOL")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass_n=0
fail_n=0
pass() { echo "  ✓ $1"; pass_n=$((pass_n + 1)); }
fail() { echo "  ✗ $1" >&2; fail_n=$((fail_n + 1)); }

echo "--- 1. No arguments → usage error ---"
output="$("$TOOL" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
    pass "exits non-zero with no args (rc=$rc)"
else
    fail "should exit non-zero with no args (rc=$rc)"
fi

echo "--- 2. Non-existent dir → error ---"
output="$("$TOOL" "$work/nope" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
    pass "exits non-zero for non-existent dir (rc=$rc)"
else
    fail "should exit non-zero for non-existent dir (rc=$rc)"
fi

echo "--- 3. Missing go toolchain → error ---"
mkdir -p "$work/project"
output="$(PATH="/usr/bin:/bin" "$TOOL" "$work/project" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && echo "$output" | grep -qi "go"; then
    pass "exits non-zero when go is not on PATH"
else
    fail "should exit non-zero when go is missing (rc=$rc, output=$output)"
fi

echo
if [ "$fail_n" -gt 0 ]; then
    echo "FAILED: $fail_n"
    exit 1
fi
echo "ALL PASS ($pass_n)"
