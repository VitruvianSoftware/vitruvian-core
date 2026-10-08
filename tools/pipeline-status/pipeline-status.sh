#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# pipeline-status — Deterministic verification of all GitHub Actions workflows on main for a commit/PR.
#
# Exit codes:
#   0: All workflows on main completed successfully (VERIFIED GREEN).
#   1: One or more workflows failed (FAILED).
#   2: Workflows are currently in-flight (IN PROGRESS / QUEUED).
#   3: No workflows found or argument resolution error.
set -uo pipefail

REPO="${PIPELINE_REPO:-VitruvianSoftware/vitruvian-core}"

info() { printf '\033[36m→\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m⏳\033[0m %s\n' "$*"; }
die()  { printf '\033[31m✗\033[0m %s\n' "$*" >&2; }

# Pure evaluation function (unit tested): parses JSON output of GitHub Actions runs
evaluate_runs_json() {
  local json="$1"

  if command -v jq >/dev/null 2>&1; then
    local eval_data
    eval_data=$(echo "$json" | jq -r '
      ([.workflow_runs[]? | select((.name != null) or (.workflow_id != null))] | group_by(.workflow_id // .name) | map(sort_by(.id // 0) | last)) as $latest |
      if ($latest | length) == 0 then
        "NO_RUNS|3"
      else
        ([$latest[] | select(.conclusion == "failure" or .conclusion == "timed_out" or .conclusion == "startup_failure")] | length) as $failed |
        ([$latest[] | select(.status == "in_progress" or .status == "queued" or .status == "pending" or .status == "waiting")] | length) as $in_flight |
        ([$latest[] | select(.conclusion == "success" or .conclusion == "skipped" or .conclusion == "neutral")] | length) as $passed |
        ($latest | length) as $total |
        if $failed > 0 then
          "FAILED: \($failed) failed, \($in_flight) in-flight, \($passed) passed out of \($total) total|1"
        elif $in_flight > 0 then
          "IN_PROGRESS: \($in_flight) in-flight, \($passed) passed out of \($total) total|2"
        else
          "ALL_PASSED: \($passed) passed out of \($total) total|0"
        end
      end
    ')

    local msg="${eval_data%|*}"
    local rc="${eval_data##*|}"
    echo "$msg"
    return "$rc"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    print("NO_RUNS")
    sys.exit(3)
runs = data.get("workflow_runs") or []
if not runs:
    print("NO_RUNS")
    sys.exit(3)

latest = {}
for r in sorted(runs, key=lambda x: x.get("id", 0)):
    key = r.get("workflow_id") or r.get("name")
    if key:
        latest[key] = r

items = list(latest.values())
if not items:
    print("NO_RUNS")
    sys.exit(3)

total = len(items)
failed = sum(1 for r in items if r.get("conclusion") in ("failure", "timed_out", "startup_failure"))
in_flight = sum(1 for r in items if r.get("status") in ("in_progress", "queued", "pending", "waiting"))
passed = sum(1 for r in items if r.get("conclusion") in ("success", "skipped", "neutral"))

if failed > 0:
    print(f"FAILED: {failed} failed, {in_flight} in-flight, {passed} passed out of {total} total")
    sys.exit(1)
elif in_flight > 0:
    print(f"IN_PROGRESS: {in_flight} in-flight, {passed} passed out of {total} total")
    sys.exit(2)
else:
    print(f"ALL_PASSED: {passed} passed out of {total} total")
    sys.exit(0)
' "$json"
    return $?
  else
    echo "NO_RUNS (neither jq nor python3 available)" >&2
    return 3
  fi
}

main() {
  local target="${1:-HEAD}"
  local sha=""

  cd "${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}" || {
    die "cannot find a workspace to run in"
    exit 3
  }

  command -v gh >/dev/null 2>&1 || { die "gh CLI not found on PATH"; exit 3; }
  if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
    die "neither jq nor python3 found on PATH"
    exit 3
  fi

  if [[ "$target" =~ ^#?[0-9]+$ ]]; then
    local pr="${target#\#}"
    sha=$(gh pr view "$pr" --repo "$REPO" --json mergeCommit -q '.mergeCommit.oid // empty' 2>/dev/null || true)
    [ -n "$sha" ] || sha=$(gh pr view "$pr" --repo "$REPO" --json headRefOid -q '.headRefOid // empty' 2>/dev/null || true)
    if [ -z "$sha" ]; then
      # Fallback: check if the commit already landed on origin/main via squash title suffix "(#$pr)"
      git fetch origin main -q 2>/dev/null || true
      sha=$(git log -1 --grep "(#${pr})" --format='%H' origin/main 2>/dev/null || true)
    fi
  elif [ "$target" = "HEAD" ]; then
    sha=$(git rev-parse HEAD 2>/dev/null || true)
  else
    sha=$(git rev-parse "$target" 2>/dev/null || echo "$target")
  fi

  if [ -z "$sha" ]; then
    die "Could not resolve target '$target' to a valid commit SHA"
    exit 3
  fi

  info "Checking GitHub Actions pipeline status for commit ${sha:0:8} in ${REPO}..."

  local runs_json
  runs_json=$(gh api "repos/${REPO}/actions/runs?head_sha=${sha}&per_page=100" 2>/dev/null || echo '{"total_count":0,"workflow_runs":[]}')

  local eval_output
  eval_output=$(evaluate_runs_json "$runs_json")
  local rc=$?

  case $rc in
    0)
      ok "All post-merge workflows for ${sha:0:8} are GREEN ($eval_output)"
      exit 0
      ;;
    1)
      die "Pipeline FAILED for commit ${sha:0:8} ($eval_output)"
      if command -v jq >/dev/null 2>&1; then
        echo "$runs_json" | jq -r '.workflow_runs[]? | select(.conclusion == "failure" or .conclusion == "timed_out") | "  - \(.name): \(.html_url)"' >&2
      elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import json, sys; [print(f"  - {r.get(\"name\")}: {r.get(\"html_url\")}", file=sys.stderr) for r in json.loads(sys.argv[1]).get("workflow_runs", []) if r.get("conclusion") in ("failure", "timed_out")]' "$runs_json"
      fi
      exit 1
      ;;
    2)
      warn "Pipeline is currently IN PROGRESS for commit ${sha:0:8} ($eval_output)"
      if command -v jq >/dev/null 2>&1; then
        echo "$runs_json" | jq -r '.workflow_runs[]? | select(.status == "in_progress" or .status == "queued") | "  - \(.name) (\(.status)): \(.html_url)"'
      elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import json, sys; [print(f"  - {r.get(\"name\")} ({r.get(\"status\")}): {r.get(\"html_url\")}") for r in json.loads(sys.argv[1]).get("workflow_runs", []) if r.get("status") in ("in_progress", "queued")]' "$runs_json"
      fi
      exit 2
      ;;
    *)
      warn "No workflow runs found yet for commit ${sha:0:8}"
      exit 3
      ;;
  esac
}

if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  main "$@"
fi
