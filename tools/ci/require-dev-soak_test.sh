#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Unit tests for require-dev-soak.sh. Drives the real script against a STUBBED
# `gh` (GH_BIN), so every branch is exercised with no network, no token and no
# GitHub state — the same hermetic bar as resolve-deploy-base_test.sh.
#
# Locates the script beside itself (matching resolve-deploy-base_test.sh, which
# CI invokes with no arguments); an explicit path may still be passed as $1.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${1:-${HERE}/require-dev-soak.sh}"
fails=0
ok() { echo "ok - $1"; }
bad() { echo "NOT OK - $1"; fails=$((fails + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

# Stub `gh`. Behaviour is driven by files in $WORK so each case can reshape it:
#   runs.txt  -> newline-separated run ids for `gh run list`
#   jobs.<id> -> "<name>\t<conclusion>" lines for `gh run view <id>`
#   list_rc   -> optional forced exit code for `gh run list`
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
W="$GH_STUB_DIR"
case "$1 $2" in
  "api repos"*)
    # Workflow resolution from the current run id. `api_workflow` holds the id
    # to return; its absence simulates the lookup failing.
    if [ -f "$W/api_workflow" ]; then cat "$W/api_workflow"; else exit 1; fi
    ;;
  "run list")
    if [ -f "$W/list_rc" ]; then
      echo "simulated gh failure" >&2
      exit "$(cat "$W/list_rc")"
    fi
    cat "$W/runs.txt" 2>/dev/null
    ;;
  "run view")
    id="$3"
    if [ -f "$W/jobs.$id" ]; then
      cat "$W/jobs.$id"
    else
      # No jobs file => simulate an API error for this run.
      echo "no such run" >&2
      exit 1
    fi
    ;;
  *) echo "unexpected gh invocation: $*" >&2; exit 99 ;;
esac
STUB
chmod +x "$WORK/bin/gh"

export GH_STUB_DIR="$WORK"

run_gate() { # runs the script with a clean env; echoes output, returns its rc
  GH_BIN="$WORK/bin/gh" \
  REPO="acme/repo" \
  WORKFLOW_FILE="${WORKFLOW_FILE-tabula-deploy.yaml}" \
  DEV_JOB_NAME="deploy-dev / deploy" \
  ALLOW_UNSOAKED="${ALLOW_UNSOAKED:-false}" \
  SCAN_LIMIT=20 \
    bash "$SCRIPT" 2>&1
}

reset() { rm -f "$WORK"/runs.txt "$WORK"/jobs.* "$WORK"/list_rc "$WORK"/api_workflow; }

# --- the core case this gate exists for: development is RED ----------------
reset
printf '900\n899\n' >"$WORK/runs.txt"
printf 'build\tsuccess\ndeploy-dev / deploy\tfailure\n' >"$WORK/jobs.900"
out="$(run_gate)"; rc=$?
[ "$rc" -eq 1 ] && ok "a failed dev deploy BLOCKS the promotion (exit 1)" \
  || bad "expected exit 1 on a red dev deploy, got $rc:\n$out"
echo "$out" | grep -q '::error' \
  && ok "blocking emits a GitHub ::error annotation" || bad "expected ::error:\n$out"
echo "$out" | grep -q 'actions/runs/900' \
  && ok "the block names the offending run" || bad "expected the run URL:\n$out"

# --- healthy development promotes ------------------------------------------
reset
printf '900\n' >"$WORK/runs.txt"
printf 'deploy-dev / deploy\tsuccess\n' >"$WORK/jobs.900"
out="$(run_gate)"; rc=$?
[ "$rc" -eq 0 ] && ok "a green dev deploy allows the promotion" || bad "expected exit 0:\n$out"

# --- `skipped` is a PASS, not a failure (the docs/CLI-only trap) -----------
# The graph gate legitimately skips deploy-dev when no deployable artifact
# changed. Treating that as red would wedge those releases forever.
reset
printf '900\n' >"$WORK/runs.txt"
printf 'deploy-dev / deploy\tskipped\n' >"$WORK/jobs.900"
out="$(run_gate)"; rc=$?
[ "$rc" -eq 0 ] && ok "a SKIPPED dev deploy passes (nothing to soak)" || bad "expected exit 0 on skipped:\n$out"

# --- newest run decides, not an older green one ----------------------------
# Guards the regression where an old success masks a current failure.
reset
printf '900\n899\n' >"$WORK/runs.txt"
printf 'deploy-dev / deploy\tfailure\n' >"$WORK/jobs.900"
printf 'deploy-dev / deploy\tsuccess\n' >"$WORK/jobs.899"
out="$(run_gate)"; rc=$?
[ "$rc" -eq 1 ] && ok "the NEWEST terminal result decides (old green cannot mask new red)" \
  || bad "expected the newest (failed) run to win, got $rc:\n$out"

# --- runs where the job never materialised are skipped, not counted --------
reset
printf '900\n899\n' >"$WORK/runs.txt"
printf 'build\tsuccess\n' >"$WORK/jobs.900"          # job absent entirely
printf 'deploy-dev / deploy\tfailure\n' >"$WORK/jobs.899"
out="$(run_gate)"; rc=$?
[ "$rc" -eq 1 ] && ok "a run without the job is not evidence; scanning continues to the real result" \
  || bad "expected to skip past the jobless run to the failure, got $rc:\n$out"

# --- per-service isolation: another service's red must not block us --------
reset
printf '900\n' >"$WORK/runs.txt"
printf 'deploy-dev-web / deploy\tfailure\ndeploy-dev / deploy\tsuccess\n' >"$WORK/jobs.900"
out="$(run_gate)"; rc=$?
[ "$rc" -eq 0 ] && ok "a DIFFERENT service's red dev deploy does not block this one" \
  || bad "expected exit 0 (only deploy-dev/deploy matters here), got $rc:\n$out"

# --- fail OPEN on indeterminate --------------------------------------------
reset
echo 1 >"$WORK/list_rc"
out="$(run_gate)"; rc=$?
[ "$rc" -eq 0 ] && ok "an API failure fails OPEN (warns, allows)" || bad "expected exit 0 on API error:\n$out"
echo "$out" | grep -q '::warning' \
  && ok "the indeterminate path emits a ::warning" || bad "expected ::warning:\n$out"

reset
: >"$WORK/runs.txt"   # no runs at all
out="$(run_gate)"; rc=$?
[ "$rc" -eq 0 ] && ok "no run history fails OPEN" || bad "expected exit 0 with no runs:\n$out"

reset
printf '900\n' >"$WORK/runs.txt"
printf 'build\tsuccess\n' >"$WORK/jobs.900"   # job never found in the window
out="$(run_gate)"; rc=$?
[ "$rc" -eq 0 ] && ok "job absent from the whole scan window fails OPEN" || bad "expected exit 0:\n$out"

# --- break-glass override ---------------------------------------------------
reset
printf '900\n' >"$WORK/runs.txt"
printf 'deploy-dev / deploy\tfailure\n' >"$WORK/jobs.900"
out="$(ALLOW_UNSOAKED=true run_gate)"; rc=$?
[ "$rc" -eq 0 ] && ok "ALLOW_UNSOAKED=true overrides even a red development" \
  || bad "expected the override to pass, got $rc:\n$out"
echo "$out" | grep -q '::warning' \
  && ok "the override is logged loudly as a ::warning" || bad "expected ::warning on override:\n$out"

# --- workflow resolution: derived from the CURRENT run, not a ref basename ---
# A reusable workflow's jobs run inside the CALLER's run, so GITHUB_RUN_ID
# identifies the caller. Getting this wrong would query the wrong history and
# silently fail open -- a gate that is a no-op while looking like protection.
reset
echo "oauth-user-inspector-deploy.yaml" >"$WORK/api_workflow"
printf '900\n' >"$WORK/runs.txt"
printf 'deploy-dev / deploy\tfailure\n' >"$WORK/jobs.900"
out="$(WORKFLOW_FILE= GITHUB_RUN_ID=4242 run_gate)"; rc=$?
[ "$rc" -eq 1 ] && ok "resolves the workflow from GITHUB_RUN_ID and still blocks on red" \
  || bad "expected the run-id-resolved workflow to be searched, got $rc:\n$out"
echo "$out" | grep -q 'searching oauth-user-inspector-deploy.yaml' \
  && ok "logs which workflow history it searched" || bad "expected the searched workflow to be logged:\n$out"

# An explicit WORKFLOW_FILE still wins over run-id resolution.
reset
echo "wrong-workflow.yaml" >"$WORK/api_workflow"
printf '900\n' >"$WORK/runs.txt"
printf 'deploy-dev / deploy\tfailure\n' >"$WORK/jobs.900"
out="$(run_gate)"; rc=$?
echo "$out" | grep -q 'searching tabula-deploy.yaml' \
  && ok "an explicit WORKFLOW_FILE overrides run-id resolution" || bad "expected the explicit override to win:\n$out"

# Resolution failing entirely (no run id, no ref) fails OPEN, never a false block.
reset
printf '900\n' >"$WORK/runs.txt"
printf 'deploy-dev / deploy\tfailure\n' >"$WORK/jobs.900"
out="$(WORKFLOW_FILE= GITHUB_RUN_ID= GITHUB_WORKFLOW_REF= run_gate)"; rc=$?
[ "$rc" -eq 0 ] && ok "unresolvable workflow fails OPEN (never a false block)" \
  || bad "expected exit 0 when the workflow cannot be resolved, got $rc:\n$out"

echo "---"
if [ "$fails" -eq 0 ]; then echo "PASS (all require-dev-soak checks)"; exit 0; fi
echo "FAIL ($fails check(s))"; exit 1
