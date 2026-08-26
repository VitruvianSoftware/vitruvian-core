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
  local total failed in_flight passed

  total=$(echo "$json" | jq '.total_count // (.workflow_runs | length)')
  if [ -z "$total" ] || [ "$total" -eq 0 ]; then
    echo "NO_RUNS"
    return 3
  fi

  failed=$(echo "$json" | jq -r '[.workflow_runs[] | select(.conclusion == "failure" or .conclusion == "timed_out" or .conclusion == "startup_failure")] | length')
  in_flight=$(echo "$json" | jq -r '[.workflow_runs[] | select(.status == "in_progress" or .status == "queued" or .status == "pending" or .status == "waiting")] | length')
  passed=$(echo "$json" | jq -r '[.workflow_runs[] | select(.conclusion == "success" or .conclusion == "skipped" or .conclusion == "neutral")] | length')

  if [ "$failed" -gt 0 ]; then
    echo "FAILED: $failed failed, $in_flight in-flight, $passed passed out of $total total"
    return 1
  elif [ "$in_flight" -gt 0 ]; then
    echo "IN_PROGRESS: $in_flight in-flight, $passed passed out of $total total"
    return 2
  else
    echo "ALL_PASSED: $passed passed out of $total total"
    return 0
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
  command -v jq >/dev/null 2>&1 || { die "jq not found on PATH"; exit 3; }

  # Resolve target to a commit SHA
  case "$target" in
    '#'*|[0-9]*)
      local pr="${target#\#}"
      sha=$(gh pr view "$pr" --repo "$REPO" --json mergeCommit -q '.mergeCommit.oid // empty' 2>/dev/null || true)
      [ -n "$sha" ] || sha=$(gh pr view "$pr" --repo "$REPO" --json headRefOid -q '.headRefOid // empty' 2>/dev/null || true)
      ;;
    HEAD)
      sha=$(git rev-parse HEAD 2>/dev/null || true)
      ;;
    *)
      sha=$(git rev-parse "$target" 2>/dev/null || echo "$target")
      ;;
  esac

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
      echo "$runs_json" | jq -r '.workflow_runs[] | select(.conclusion == "failure" or .conclusion == "timed_out") | "  - \(.name): \(.html_url)"' >&2
      exit 1
      ;;
    2)
      warn "Pipeline is currently IN PROGRESS for commit ${sha:0:8} ($eval_output)"
      echo "$runs_json" | jq -r '.workflow_runs[] | select(.status == "in_progress" or .status == "queued") | "  - \(.name) (\(.status)): \(.html_url)"'
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
EOF && chmod +x tools/pipeline-status/pipeline-status.sh