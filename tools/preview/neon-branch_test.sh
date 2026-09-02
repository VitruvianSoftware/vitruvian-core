#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Unit tests for tools/preview/neon-branch.sh
set -uo pipefail

SCRIPT="${1:?usage: neon-branch_test.sh <path-to-neon-branch.sh>}"
fails=0
ok() { echo "ok - $1"; }
bad() { echo "NOT OK - $1"; fails=$((fails + 1)); }

# Test 1: Missing action fails
if "$SCRIPT" >/dev/null 2>&1; then
  bad "missing action should fail with non-zero exit code"
else
  ok "missing action exits non-zero"
fi

# Test 2: Dry-run create outputs valid JSON with expected keys
out="$("$SCRIPT" create --dry-run --branch-name "tabula-pr-100" --project-id "prj-123" --api-key "dummy")"
if echo "$out" | grep -q '"dry_run": true' && echo "$out" | grep -q '"action": "create"'; then
  ok "dry-run create emits valid JSON with action=create"
else
  bad "dry-run create failed to emit valid JSON (got: $out)"
fi

# Test 3: Dry-run delete outputs valid JSON
out="$("$SCRIPT" delete --dry-run --branch-name "tabula-pr-100")"
if echo "$out" | grep -q '"dry_run": true' && echo "$out" | grep -q '"action": "delete"'; then
  ok "dry-run delete emits valid JSON with action=delete"
else
  bad "dry-run delete failed to emit valid JSON"
fi

# Test 4: Missing project-id in live mode fails
if "$SCRIPT" create --api-key "dummy" --branch-name "tabula-pr-100" >/dev/null 2>&1; then
  bad "live create without project-id should fail"
else
  ok "live create without project-id fails closed"
fi

# Test 5: Missing api-key in live mode fails
if "$SCRIPT" create --project-id "prj-123" --branch-name "tabula-pr-100" >/dev/null 2>&1; then
  bad "live create without api-key should fail"
else
  ok "live create without api-key fails closed"
fi

echo "Neon branch tests completed: $((5 - fails))/5 passed."
exit "$fails"
