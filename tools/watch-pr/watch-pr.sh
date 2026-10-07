#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# watch-pr — Autonomous, robust monitoring of GitHub Actions CI checks,
# merge queue ingestion, squash landing, and post-merge pipeline health.
#
# Usage:
#   bazel run //tools/watch-pr -- <pr-number|branch|sha> [options]
#
# Options:
#   --timeout <sec>      Max time to wait before timing out (default: 2700 / 45m).
#   --interval <sec>     Polling interval between checks (default: 15).
#   --skip-post-merge    Exit immediately after landing on main, skipping post-merge pipeline.
#   --help, -h           Show this help message.
#
# Exit codes:
#   0: Successfully verified: PR checks passed, landed on main, and post-merge workflows green.
#   1: Failure detected in CI checks, merge queue, or post-merge workflows (diagnostics printed).
#   2: Timeout reached.
#   3: Invalid argument or configuration error.
set -uo pipefail

REPO="${WATCH_PR_REPO:-VitruvianSoftware/vitruvian-core}"
TIMEOUT="${WATCH_PR_TIMEOUT:-2700}"
INTERVAL="${WATCH_PR_INTERVAL:-15}"
SKIP_POST_MERGE="${WATCH_PR_SKIP_POST_MERGE:-false}"

info() { printf '\033[36m[%s] →\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()   { printf '\033[32m[%s] ✓\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\033[33m[%s] ⏳\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
die()  { printf '\033[31m[%s] ✗\033[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

usage() {
  cat <<'EOF'
watch-pr — Autonomous PR CI check, merge queue, and post-merge watchdog.

Usage:
  bazel run //tools/watch-pr -- <pr-number|branch|sha> [options]

Arguments:
  <pr-number>         Pull request number (e.g. 2857 or #2857)
  <branch>            Branch name associated with an open or merged PR
  <sha>               Commit SHA associated with a PR

Options:
  --timeout <sec>     Max duration in seconds before giving up (default: 2700)
  --interval <sec>    Seconds between polling status queries (default: 15)
  --skip-post-merge   Exit once merged on main without waiting for post-merge pipeline
  --help, -h          Print this help message

Exit codes:
  0: Success (all checks passed, merged, post-merge green)
  1: Check or workflow failure (diagnostic logs printed)
  2: Timeout reached
  3: Invalid argument or configuration error
EOF
}

# Pure parsing helper for PR check JSON output (unit tested)
parse_checks_json() {
  local json="$1"

  if command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys

try:
    checks = json.loads(sys.argv[1])
except Exception as e:
    print(f"PARSE_ERROR: {e}")
    sys.exit(3)

passed = 0
skipped = 0
pending = 0
failed = 0
failed_details = []

for c in checks:
    bucket = c.get("bucket", "")
    state = str(c.get("state", "")).upper()
    name = c.get("name", "unknown")
    workflow = c.get("workflow", "")
    link = c.get("link", "") or c.get("url", "")

    if bucket == "fail" or state in ("FAILURE", "FAILED", "ERROR", "TIMED_OUT", "STARTUP_FAILURE", "CANCELLED"):
        failed += 1
        failed_details.append(f"{name}|{workflow}|{link}")
    elif bucket == "pending" or state in ("IN_PROGRESS", "QUEUED", "PENDING", "WAITING", ""):
        pending += 1
    elif bucket == "pass" or state in ("SUCCESS", "NEUTRAL"):
        passed += 1
    elif bucket == "skipping" or state == "SKIPPED":
        skipped += 1
    else:
        pending += 1

print(f"{passed}:{skipped}:{pending}:{failed}")
for fd in failed_details:
    print(f"FAILED_ITEM:{fd}")
' "$json"
  elif command -v jq >/dev/null 2>&1; then
    local passed skipped pending failed
    passed=$(echo "$json" | jq -r '[.[] | select(.bucket == "pass" or .state == "SUCCESS" or .state == "NEUTRAL")] | length')
    skipped=$(echo "$json" | jq -r '[.[] | select(.bucket == "skipping" or .state == "SKIPPED")] | length')
    failed=$(echo "$json" | jq -r '[.[] | select(.bucket == "fail" or .state == "FAILURE" or .state == "FAILED" or .state == "ERROR" or .state == "TIMED_OUT" or .state == "STARTUP_FAILURE" or .state == "CANCELLED")] | length')
    pending=$(echo "$json" | jq -r '[.[] | select(.bucket == "pending" or .state == "IN_PROGRESS" or .state == "QUEUED" or .state == "PENDING" or .state == "WAITING")] | length')
    echo "${passed}:${skipped}:${pending}:${failed}"
    echo "$json" | jq -r '.[] | select(.bucket == "fail" or .state == "FAILURE" or .state == "FAILED" or .state == "ERROR" or .state == "TIMED_OUT") | "FAILED_ITEM:\(.name)|\(.workflow)|\(.link // .url)"'
  else
    echo "ERROR: neither python3 nor jq available" >&2
    return 3
  fi
}

main() {
  local target=""

  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --timeout)
        TIMEOUT="$2"
        shift 2
        ;;
      --interval)
        INTERVAL="$2"
        shift 2
        ;;
      --skip-post-merge)
        SKIP_POST_MERGE=true
        shift
        ;;
      -*)
        die "Unknown option: $1"
        usage
        exit 3
        ;;
      *)
        if [ -z "$target" ]; then
          target="$1"
          shift
        else
          die "Unexpected extra argument: $1"
          exit 3
        fi
        ;;
    esac
  done

  if [ -z "$target" ]; then
    die "Missing target pull request number, branch, or commit SHA."
    usage
    exit 3
  fi

  cd "${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}" || {
    die "Cannot find a repository workspace to run in."
    exit 3
  }

  command -v gh >/dev/null 2>&1 || { die "gh CLI not found on PATH"; exit 3; }

  # Ensure GitHub auth token is active; if unset, attempt to initialize via agent-app
  if [ -z "${GH_TOKEN:-}" ]; then
    if [ -f "tools/agent-app/BUILD" ] && command -v bazel >/dev/null 2>&1; then
      eval "$(bazel run //tools/agent-app -- env scout 2>/dev/null || true)"
    fi
  fi

  # Resolve target to PR number
  local pr=""
  case "$target" in
    '#'*) pr="${target#\#}" ;;
    *[!0-9]*)
      # Not purely numeric; try resolving as branch name
      pr=$(gh pr list --repo "$REPO" --head "$target" --state all \
           --json number,createdAt -q 'sort_by(.createdAt)|last|.number' 2>/dev/null || true)
      if [ -z "$pr" ] || [ "$pr" = "null" ]; then
        # Try resolving as commit SHA
        pr=$(gh api "repos/${REPO}/commits/${target}/pulls" \
             -q 'sort_by(.created_at)|last|.number' 2>/dev/null || true)
      fi
      ;;
    *) pr="$target" ;;
  esac

  if [ -z "$pr" ] || [ "$pr" = "null" ]; then
    # Final fallback: check if commit log on origin/main matches target
    local commit_on_main
    commit_on_main=$(git log -1 --grep "(#${target})" --format='%H' origin/main 2>/dev/null || true)
    if [ -n "$commit_on_main" ]; then
      pr="$target"
    else
      die "Could not resolve '$target' to a valid pull request in $REPO."
      exit 3
    fi
  fi

  info "Starting autonomous watchdog for PR #${pr} in ${REPO} (timeout: ${TIMEOUT}s, interval: ${INTERVAL}s)..."

  local start_time
  start_time=$(date +%s)
  local deadline=$((start_time + TIMEOUT))

  # ── Phase 1: Watch PR CI Checks ─────────────────────────────────────────────
  local checks_passed=false
  local pr_merged=false

  while true; do
    local now
    now=$(date +%s)
    if [ "$now" -ge "$deadline" ]; then
      die "Watchdog timed out after ${TIMEOUT}s waiting for PR #${pr}."
      exit 2
    fi
    local elapsed=$((now - start_time))

    # Check if PR already merged while checks were running
    local pr_view_json
    pr_view_json=$(gh pr view "$pr" --repo "$REPO" --json state,mergeStateStatus,mergeCommit 2>/dev/null || true)
    local pr_state
    pr_state=$(echo "$pr_view_json" | grep -o '"state":"[^"]*"' | cut -d'"' -f4 || true)

    if [ "$pr_state" = "MERGED" ]; then
      ok "PR #${pr} has already merged into main!"
      pr_merged=true
      checks_passed=true
      break
    fi

    # Query checks
    local checks_json
    checks_json=$(gh pr checks "$pr" --repo "$REPO" --json name,state,bucket,workflow,link 2>/dev/null || true)

    if [ -z "$checks_json" ] || [ "$checks_json" = "[]" ] || [ "$checks_json" = "null" ]; then
      # If checks list is empty, verify if squashed commit already landed on main
      local local_match
      local_match=$(git log -1 --grep "(#${pr})" --format='%H' origin/main 2>/dev/null || true)
      if [ -n "$local_match" ]; then
        ok "PR #${pr} squashed commit ${local_match:0:8} already detected on origin/main!"
        pr_merged=true
        checks_passed=true
        break
      fi
      warn "Waiting for PR #${pr} checks to be registered by GitHub Actions... (${elapsed}s elapsed)"
      sleep "$INTERVAL"
      continue
    fi

    local parsed_output
    parsed_output=$(parse_checks_json "$checks_json")
    local stats_line
    stats_line=$(echo "$parsed_output" | head -n1)
    local p s pend f
    IFS=':' read -r p s pend f <<< "$stats_line"

    if [ "$f" -gt 0 ]; then
      die "Check failure detected on PR #${pr}: ${f} failing check(s)!"
      echo "$parsed_output" | grep "^FAILED_ITEM:" | while IFS='|' read -r item workflow link; do
        local name="${item#FAILED_ITEM:}"
        die "  - ${name} (${workflow}): ${link}"
        # Extract run ID if available from URL and attempt to fetch failed logs
        local run_id
        run_id=$(echo "$link" | grep -o '/runs/[0-9]*' | cut -d'/' -f3 || true)
        if [ -n "$run_id" ]; then
          info "Fetching failure logs for run ${run_id}:"
          gh run view "$run_id" --repo "$REPO" --log-failed 2>/dev/null | tail -n 25 || true
        fi
      done
      exit 1
    fi

    if [ "$pend" -eq 0 ] && [ "$p" -gt 0 ]; then
      ok "All PR #${pr} checks PASSED (${p} passed, ${s} skipped) in ${elapsed}s!"
      checks_passed=true
      break
    fi

    warn "PR #${pr} checks in progress: ${p} passed, ${s} skipped, ${pend} pending, 0 failed (${elapsed}s elapsed)"
    sleep "$INTERVAL"
  done

  # ── Phase 2: Watch Merge Queue / Squash Merge into main ─────────────────────
  if [ "$pr_merged" = false ]; then
    info "Monitoring merge queue / squash merge for PR #${pr} into main..."

    while true; do
      local now
      now=$(date +%s)
      if [ "$now" -ge "$deadline" ]; then
        die "Watchdog timed out after ${TIMEOUT}s waiting for PR #${pr} to merge."
        exit 2
      fi
      local elapsed=$((now - start_time))

      # Local git check first (fast and completely deterministic)
      git fetch origin main -q 2>/dev/null || true
      local local_match
      local_match=$(git log -1 --grep "(#${pr})" --format='%H' origin/main 2>/dev/null || true)
      if [ -n "$local_match" ]; then
        ok "PR #${pr} squashed commit ${local_match:0:8} detected on origin/main!"
        pr_merged=true
        break
      fi

      local pr_view
      pr_view=$(gh pr view "$pr" --repo "$REPO" --json state,mergeStateStatus,mergeCommit 2>/dev/null || true)
      local state
      state=$(echo "$pr_view" | grep -o '"state":"[^"]*"' | cut -d'"' -f4 || true)

      if [ "$state" = "MERGED" ]; then
        ok "PR #${pr} is marked MERGED in GitHub!"
        pr_merged=true
        break
      elif [ "$state" = "CLOSED" ]; then
        die "PR #${pr} was closed without being merged!"
        exit 1
      fi

      local merge_state
      merge_state=$(echo "$pr_view" | grep -o '"mergeStateStatus":"[^"]*"' | cut -d'"' -f4 || echo "QUEUED")
      info "PR #${pr} status: ${state:-OPEN} (mergeStateStatus: ${merge_state:-QUEUED}). Waiting for squash merge... (${elapsed}s elapsed)"
      sleep "$INTERVAL"
    done
  fi

  # ── Phase 3: Verify Landed & Post-Merge Pipeline Status ──────────────────────
  if [ "$SKIP_POST_MERGE" = true ]; then
    ok "PR #${pr} has merged into main! (Skipping post-merge pipeline check as requested)."
    exit 0
  fi

  # Resolve squashed commit SHA
  local squashed_sha=""
  squashed_sha=$(gh pr view "$pr" --repo "$REPO" --json mergeCommit -q '.mergeCommit.oid // empty' 2>/dev/null || true)
  if [ -z "$squashed_sha" ]; then
    git fetch origin main -q 2>/dev/null || true
    squashed_sha=$(git log -1 --grep "(#${pr})" --format='%H' origin/main 2>/dev/null || true)
  fi

  if [ -z "$squashed_sha" ]; then
    die "Could not resolve squashed commit SHA for PR #${pr}."
    exit 3
  fi

  ok "PR #${pr} resolved to squashed commit ${squashed_sha:0:8} on main."
  info "Monitoring post-merge push workflows on main for commit ${squashed_sha:0:8}..."

  local pipeline_script="tools/pipeline-status/pipeline-status.sh"
  local post_merge_grace_period=60
  local post_merge_start
  post_merge_start=$(date +%s)

  while true; do
    local now
    now=$(date +%s)
    if [ "$now" -ge "$deadline" ]; then
      die "Watchdog timed out after ${TIMEOUT}s waiting for post-merge pipeline on commit ${squashed_sha:0:8}."
      exit 2
    fi
    local elapsed=$((now - start_time))

    local status_output
    local status_rc=0
    if [ -f "$pipeline_script" ]; then
      status_output=$(bash "$pipeline_script" "$squashed_sha" 2>&1) || status_rc=$?
    elif command -v bazel >/dev/null 2>&1; then
      status_output=$(bazel run //tools/pipeline-status -- "$squashed_sha" 2>&1) || status_rc=$?
    else
      warn "Neither pipeline-status.sh nor bazel available; skipping post-merge pipeline check."
      exit 0
    fi

    case $status_rc in
      0)
        ok "All post-merge push workflows for commit ${squashed_sha:0:8} are GREEN!"
        echo "$status_output" | grep -E "(✓|passed)" || true
        ok "PR #${pr} successfully watched from submission to green post-merge pipeline on main! (Total time: ${elapsed}s)"
        exit 0
        ;;
      1)
        die "Post-merge pipeline FAILED on main for commit ${squashed_sha:0:8}!"
        echo "$status_output" >&2
        exit 1
        ;;
      2)
        warn "Post-merge push workflows are currently IN PROGRESS / QUEUED... (${elapsed}s elapsed)"
        sleep "$INTERVAL"
        ;;
      3)
        local post_elapsed=$((now - post_merge_start))
        if [ "$post_elapsed" -lt "$post_merge_grace_period" ]; then
          info "Waiting for GitHub Actions to register push workflows for ${squashed_sha:0:8}... (${post_elapsed}s/${post_merge_grace_period}s grace period)"
          sleep "$INTERVAL"
        else
          # If no workflow runs are configured for this change or runs completed before check
          ok "No further workflow runs pending for commit ${squashed_sha:0:8}."
          ok "PR #${pr} successfully verified and landed on main! (Total time: ${elapsed}s)"
          exit 0
        fi
        ;;
      *)
        warn "Unexpected pipeline-status return code ($status_rc). Retrying in ${INTERVAL}s..."
        sleep "$INTERVAL"
        ;;
    esac
  done
}

if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  main "$@"
fi
