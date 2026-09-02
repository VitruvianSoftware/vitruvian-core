#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Master E2E Dashboard Test Suite Runner
# Orchestrates execution of Tiers 1-4 for Grafana Dashboards, aggregates verdicts,
# and emits TAP / JSON / Text reports.
set -uo pipefail

resolve_workspace_root() {
	local target="${1:-$0}"
	while [ -L "$target" ]; do
		local dir="$(cd -P "$(dirname "$target")" && pwd)"
		target="$(readlink "$target")"
		[[ $target != /* ]] && target="$dir/$target"
	done
	local cur="$(cd -P "$(dirname "$target")" && pwd)"
	while [ "$cur" != "/" ] && [ -n "$cur" ]; do
		if [ -f "$cur/MODULE.bazel" ] || [ -f "$cur/go.work" ]; then
			echo "$cur"
			return 0
		fi
		cur="$(dirname "$cur")"
	done
	echo "${BUILD_WORKSPACE_DIRECTORY:-$PWD}"
}

ROOT="${BUILD_WORKSPACE_DIRECTORY:-$(resolve_workspace_root "${BASH_SOURCE[0]}")}"
cd "$ROOT"

SCRIPT_DIR="$ROOT/tests/e2e/dashboards"
TIER_FILTER="all"
FORMAT="text"
VERBOSE=false
ALLOW_OFFLINE=false

usage() {
	cat << USAGE_EOF
Usage: $(basename "$0") [options]

Options:
  --tier <1|2|3|4|all>       Execute specific test tier (default: all)
  --format <text|tap|json>   Output format (default: text)
  --allow-offline            Allow skipping Tier 4 live queries if cluster is unreachable
  -v, --verbose              Enable verbose test output
  -h, --help                 Show this help message

Test Tiers:
  Tier 1: Schema & Structure Validation (JSON syntax, UIDs, variables, panels, gridPos)
  Tier 2: PromQL Syntax & Metric Integrity (syntax parse, time units ms vs s, aggregations)
  Tier 3: GitOps Integration & Consistency (kustomization.yaml, sidecar discoverability)
  Tier 4: Live Telemetry Verification (instant queries against Thanos Querier)
USAGE_EOF
	exit "${1:-0}"
}

while [ $# -gt 0 ]; do
	case "$1" in
	--tier)
		TIER_FILTER="$2"
		shift 2
		;;
	--format)
		FORMAT="$2"
		shift 2
		;;
	--allow-offline)
		ALLOW_OFFLINE=true
		shift
		;;
	-v | --verbose)
		VERBOSE=true
		shift
		;;
	-h | --help) usage 0 ;;
	*)
		echo "ERROR: Unknown option: $1" >&2
		usage 1
		;;
	esac
done

TOTAL_TIERS=0
PASSED_TIERS=0
FAILED_TIERS=0
TOTAL_TEST_COUNT=0
PASSED_TEST_COUNT=0
FAILED_TEST_COUNT=0

START_TIME=$(python3 -c 'import time; print(int(time.time() * 1000))')
TIER_RESULTS=()

run_tier() {
	local tier_num="$1"
	local tier_name="$2"
	local script_path="$3"
	local extra_args="${4:-}"

	if [ "$TIER_FILTER" != "all" ] && [ "$TIER_FILTER" != "$tier_num" ]; then
		return 0
	fi

	TOTAL_TIERS=$((TOTAL_TIERS + 1))
	local t_start=$(python3 -c 'import time; print(int(time.time() * 1000))')

	local out
	local status=0
	if [ -f "$script_path" ]; then
		if [ -n "$extra_args" ]; then
			out="$(python3 "$script_path" "$extra_args" 2>&1)" || status=$?
		else
			out="$(python3 "$script_path" 2>&1)" || status=$?
		fi
	else
		out="Script not found: $script_path"
		status=1
	fi

	local t_end=$(python3 -c 'import time; print(int(time.time() * 1000))')
	local t_dur=$((t_end - t_start))

	local passed
	local failed
	passed=$(awk '/^[[:space:]]*ok / {c++} END {print c+0}' <<<"$out")
	failed=$(awk '/^[[:space:]]*not ok / {c++} END {print c+0}' <<<"$out")

	TOTAL_TEST_COUNT=$((TOTAL_TEST_COUNT + passed + failed))
	PASSED_TEST_COUNT=$((PASSED_TEST_COUNT + passed))
	FAILED_TEST_COUNT=$((FAILED_TEST_COUNT + failed))

	if [ "$status" -eq 0 ] && [ "$failed" -eq 0 ]; then
		PASSED_TIERS=$((PASSED_TIERS + 1))
		TIER_RESULTS+=("${tier_num}|${tier_name}|PASSED|${passed}|${failed}|${t_dur}")
		if [ "$VERBOSE" = true ]; then
			echo "$out"
		fi
	else
		FAILED_TIERS=$((FAILED_TIERS + 1))
		TIER_RESULTS+=("${tier_num}|${tier_name}|FAILED|${passed}|${failed}|${t_dur}")
		echo "$out" >&2
	fi
}

echo "================================================================================"
echo " Grafana Production Dashboards — E2E Master Test Suite"
echo " Working Directory: ${ROOT}"
echo " Tier Selection:    ${TIER_FILTER}"
echo "================================================================================"

TIER4_EXTRA=""
if [ "$ALLOW_OFFLINE" = true ]; then
	TIER4_EXTRA="--allow-offline"
fi

run_tier "1" "Schema & Structure" "$SCRIPT_DIR/tier1_schema_test.py" ""
run_tier "2" "PromQL & Metric Integrity" "$SCRIPT_DIR/tier2_promql_test.py" ""
run_tier "3" "GitOps & Consistency" "$SCRIPT_DIR/tier3_integration_test.py" ""
run_tier "4" "Live Thanos Telemetry" "$SCRIPT_DIR/tier4_telemetry_test.py" "$TIER4_EXTRA"

END_TIME=$(python3 -c 'import time; print(int(time.time() * 1000))')
TOTAL_DURATION=$((END_TIME - START_TIME))

if [ "$FORMAT" = "json" ]; then
	python3 -c '
import sys, json

tiers = []
for item in sys.argv[1:len(sys.argv)-1]:
    num, name, status, passed, failed, dur = item.split("|")
    tiers.append({
        "tier": int(num),
        "name": name,
        "status": status,
        "passed": int(passed),
        "failed": int(failed),
        "duration_ms": int(dur)
    })

payload = {
    "suite": "grafana_dashboards_e2e",
    "total_tiers": len(tiers),
    "passed_tiers": sum(1 for t in tiers if t["status"] == "PASSED"),
    "failed_tiers": sum(1 for t in tiers if t["status"] == "FAILED"),
    "total_tests": sum(t["passed"] + t["failed"] for t in tiers),
    "passed_tests": sum(t["passed"] for t in tiers),
    "failed_tests": sum(t["failed"] for t in tiers),
    "duration_ms": int(sys.argv[len(sys.argv)-1]),
    "tiers": tiers
}
print(json.dumps(payload, indent=2))
' "${TIER_RESULTS[@]}" "$TOTAL_DURATION"

elif [ "$FORMAT" = "tap" ]; then
	echo "1..${TOTAL_TIERS}"
	idx=1
	for r in "${TIER_RESULTS[@]}"; do
		IFS='|' read -r num name status passed failed dur <<<"$r"
		if [ "$status" = "PASSED" ]; then
			echo "ok ${idx} - Tier ${num}: ${name} (${passed}/${passed} passed in ${dur}ms)"
		else
			echo "not ok ${idx} - Tier ${num}: ${name} (${failed} failed in ${dur}ms)"
		fi
		idx=$((idx + 1))
	done

else
	echo
	echo "================================================================================"
	echo " Execution Matrix & Dashboard Verification Summary"
	echo "================================================================================"
	printf "| %-6s | %-28s | %-8s | %-8s | %-8s | %-10s |\n" "Tier" "Description" "Status" "Passed" "Failed" "Duration"
	echo "|--------|------------------------------|----------|----------|----------|------------|"
	for r in "${TIER_RESULTS[@]}"; do
		IFS='|' read -r num name status passed failed dur <<<"$r"
		printf "| Tier %-2s | %-28s | %-8s | %-8s | %-8s | %-8sms |\n" "$num" "$name" "$status" "$passed" "$failed" "$dur"
	done
	echo "================================================================================"
	echo " TOTALS: ${PASSED_TEST_COUNT}/${TOTAL_TEST_COUNT} tests passed across ${PASSED_TIERS}/${TOTAL_TIERS} tiers (${TOTAL_DURATION}ms total)"
	echo "================================================================================"

	if [ "$FAILED_TIERS" -eq 0 ]; then
		echo " 🎉 100% PASS RATE — GRAFANA DASHBOARDS VERIFIED FOR PRODUCTION"
	else
		echo " ❌ FAILURES DETECTED IN ${FAILED_TIERS} TIER(S)"
	fi
fi

if [ "$FAILED_TIERS" -gt 0 ]; then
	exit 1
fi
exit 0
