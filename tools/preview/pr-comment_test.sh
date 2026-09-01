#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Unit tests for tools/preview/pr-comment.sh
set -uo pipefail

SCRIPT="${1:?usage: pr-comment_test.sh <path-to-pr-comment.sh>}"
fails=0
ok() { echo "ok - $1"; }
bad() { echo "NOT OK - $1"; fails=$((fails + 1)); }

# Test 1: Missing args fails
if "$SCRIPT" >/dev/null 2>&1; then
  bad "missing args should exit non-zero"
else
  ok "missing args fails closed"
fi

# Test 2: Dry-run provisioning status renders marker
out="$("$SCRIPT" --pr 142 --app "tabula" --status provisioning --dry-run)"
if echo "$out" | grep -q "<!-- vitruvian-preview-bot: tabula -->"; then
  ok "provisioning status renders HTML marker"
else
  bad "provisioning status missing marker"
fi

# Test 3: Dry-run ready status renders table and URL
out="$("$SCRIPT" --pr 142 --app "tabula" --status ready --preview-url "https://pr-142.tabula.preview.vitruviansoftware.dev" --service-name "tabula-api-pr-142" --db-branch "tabula-pr-142" --dry-run)"
if echo "$out" | grep -q "https://pr-142.tabula.preview.vitruviansoftware.dev" && echo "$out" | grep -q "Neon copy-on-write"; then
  ok "ready status renders markdown table and database branch info"
else
  bad "ready status failed to render preview details"
fi

# Test 4: Dry-run teardown status
out="$("$SCRIPT" --pr 142 --app "tabula" --status teardown --dry-run)"
if echo "$out" | grep -q "Destroyed"; then
  ok "teardown status renders destruction notice"
else
  bad "teardown status failed to render"
fi

echo "PR comment tests completed: $((4 - fails))/4 passed."
exit "$fails"
