#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Unit tests for tools/preview/provision-preview.sh
set -uo pipefail

SCRIPT="${1:?usage: provision-preview_test.sh <path-to-provision-preview.sh>}"
fails=0
ok() { echo "ok - $1"; }
bad() { echo "NOT OK - $1"; fails=$((fails + 1)); }

# Test 1: Missing required arguments fails
if "$SCRIPT" >/dev/null 2>&1; then
  bad "execution with no args should fail"
else
  ok "missing required args fails closed"
fi

# Test 2: Dry-run execution generates expected JSON structure
out="$("$SCRIPT" --app "tabula-api" --pr 142 --dry-run)"
if echo "$out" | grep -q '"app": "tabula-api"' && echo "$out" | grep -q '"pr_number": "142"' && echo "$out" | grep -q '"status": "ready"'; then
  ok "dry-run outputs valid JSON with expected app and pr"
else
  bad "dry-run failed to emit valid preview JSON (got: $out)"
fi

# Test 3: Dry-run with neon-project-id includes simulated database branch
out="$("$SCRIPT" --app "tabula-api" --pr 142 --neon-project-id "neon-prj-123" --dry-run)"
if echo "$out" | grep -q '"database_branch": "tabula-api-pr-142"' && echo "$out" | grep -q '"database_url"'; then
  ok "dry-run with neon-project-id provisions database branch"
else
  bad "dry-run missing database_branch in output"
fi

# Test 4: Kubernetes mode dry-run
out="$("$SCRIPT" --app "tabula-api" --pr 142 --mode k8s --dry-run)"
if echo "$out" | grep -q "lab.ipv1337.dev"; then
  ok "kubernetes mode renders cluster service URL"
else
  bad "kubernetes mode failed to render cluster URL"
fi

echo "Provision preview tests completed: $((4 - fails))/4 passed."
exit "$fails"
