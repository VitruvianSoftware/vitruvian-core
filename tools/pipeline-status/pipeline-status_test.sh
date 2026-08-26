#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${1:-${HERE}/pipeline-status.sh}"
[ -f "$SCRIPT" ] || SCRIPT="${HERE}/pipeline-status.sh"
[ -f "$SCRIPT" ] || SCRIPT="tools/pipeline-status/pipeline-status.sh"
[ -f "$SCRIPT" ] || { echo "cannot find pipeline-status.sh" >&2; exit 1; }

fails=0
test_ok() { echo "  ok - $1"; }
test_bad() { echo "  NOT OK - $1" >&2; fails=$((fails + 1)); }

# Source the script under test (source-safe)
# shellcheck source=/dev/null
source "$SCRIPT"

# Test 1: Empty runs
res=$(evaluate_runs_json '{"total_count":0,"workflow_runs":[]}')
rc=$?
[ "$rc" -eq 3 ] && [ "$res" = "NO_RUNS" ] && test_ok "Empty runs return code 3" || test_bad "Empty runs failed: rc=$rc, res=$res"

# Test 2: All runs successful
all_green='{
  "total_count": 2,
  "workflow_runs": [
    {"name": "CI", "status": "completed", "conclusion": "success"},
    {"name": "delivery", "status": "completed", "conclusion": "skipped"}
  ]
}'
res=$(evaluate_runs_json "$all_green")
rc=$?
[ "$rc" -eq 0 ] && test_ok "All green returns code 0" || test_bad "All green failed: rc=$rc, res=$res"

# Test 3: In-flight runs
in_flight='{
  "total_count": 2,
  "workflow_runs": [
    {"name": "CI", "status": "completed", "conclusion": "success"},
    {"name": "delivery", "status": "in_progress", "conclusion": null}
  ]
}'
res=$(evaluate_runs_json "$in_flight")
rc=$?
[ "$rc" -eq 2 ] && test_ok "In-flight runs return code 2" || test_bad "In-flight runs failed: rc=$rc, res=$res"

# Test 4: Failed runs
failed_runs='{
  "total_count": 2,
  "workflow_runs": [
    {"name": "CI", "status": "completed", "conclusion": "failure"},
    {"name": "delivery", "status": "in_progress", "conclusion": null}
  ]
}'
res=$(evaluate_runs_json "$failed_runs")
rc=$?
[ "$rc" -eq 1 ] && test_ok "Failed runs return code 1 (failure takes precedence)" || test_bad "Failed runs failed: rc=$rc, res=$res"

if [ "$fails" -eq 0 ]; then
  echo "PASS (all pipeline-status tests passed)"
  exit 0
else
  echo "FAIL ($fails test(s) failed)"
  exit 1
fi
