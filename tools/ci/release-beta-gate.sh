#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# release-beta-gate.sh — keep a component's release PR out of auto-merge until
# the push rung that builds its artifact has SUCCEEDED for the exact code the
# release would tag. For vitruvian that rung is `vitruvian-beta`, which builds
# and publishes the beta DMG: a release whose code never produced a DMG would
# cut a tag whose production rung then fails, and that tag cannot be
# re-published (vitruvian-v3.6.0 is the case this exists for). See
# .github/workflows/release-beta-gate.yaml for when this runs, and why
# release-pr-automerge.yaml leaves this component's release PR alone.
#
# Environment:
#   REPO        owner/repo
#   COMPONENT   release-please component name, e.g. vitruvian
#   CODE_PATH   the component's directory, e.g. apps/desktop/vitruvian
#   BETA_JOB    exact delivery job name that must succeed, e.g. vitruvian-beta
#   WORKFLOW    workflow file that runs BETA_JOB on push, e.g. delivery.yaml
#   GH_TOKEN    token gh authenticates as (pull-requests: write, actions: read)
#
# Which run counts: a release-please PR is ONE commit on top of the main commit
# it releases, so that commit's first parent is what the release ships. The
# newest commit at or before it that touched CODE_PATH is the code. The beta
# that built it is not always in that commit's own run: push runs of WORKFLOW
# share one concurrency group, so a run still queued when a newer push lands is
# cancelled, and the newer run delivers its change (the orchestrator diffs from
# its last successful run). So any push run whose commit has the same CODE_PATH
# history counts. They are read newest first (the latest 20, then the code
# commit's own runs by sha if it is older than that), and the newest one whose
# BETA_JOB finished success or failure decides. A cancelled, skipped or
# unfinished job decides nothing.
#
# Decision for the open release PR:
#   success          enable auto-merge (clearing a hold this gate applied)
#   failed           hold: add do-not-automerge, disable auto-merge, comment
#   anything else    no run has decided yet: keep auto-merge off and wait;
#                    the next run's completion runs this again
#
# Exit: 0 when it decided; 1 when a lookup failed, after making sure auto-merge
# is off, so the failure is visible and the run can be re-run. A gate must not
# let a PR through on missing information.

set -uo pipefail

REPO="${REPO:?REPO must be set (owner/repo)}"
COMPONENT="${COMPONENT:?COMPONENT must be set}"
CODE_PATH="${CODE_PATH:?CODE_PATH must be set}"
BETA_JOB="${BETA_JOB:?BETA_JOB must be set}"
WORKFLOW="${WORKFLOW:?WORKFLOW must be set}"

# release-please's branch name is deterministic and per-component, so this
# targets exactly one PR and can never touch a human's branch.
BRANCH="release-please--branches--main--components--${COMPONENT}"
HOLD_LABEL="do-not-automerge"

# A fork can name its branch the same; only the in-repo release PR counts.
pr_json="$(gh pr list --repo "$REPO" --head "$BRANCH" --state open \
  --json number,headRefOid,isDraft,autoMergeRequest,labels,isCrossRepository \
  --jq 'map(select(.isCrossRepository | not)) | .[0] // empty | "\(.number)\t\(.headRefOid)\t\(.isDraft)\t\(.autoMergeRequest != null)\t\([.labels[].name] | join(","))"' 2>&1)"
if [ $? -ne 0 ]; then
  echo "::error title=release-beta-gate indeterminate::could not list open release PRs on ${BRANCH}: ${pr_json}"
  exit 1
fi
if [ -z "$pr_json" ]; then
  echo "No open release PR on ${BRANCH} — nothing to gate."
  exit 0
fi
IFS=$'\t' read -r PR HEAD_SHA IS_DRAFT AUTO_ON LABELS <<<"$pr_json"

disable_auto() {
  if [ "$AUTO_ON" = "true" ]; then
    gh pr merge "$PR" --repo "$REPO" --disable-auto ||
      echo "::warning title=auto-merge still enabled::could not disable auto-merge on #${PR}"
  fi
}

# Wait (or fail visibly) without letting the PR through.
indeterminate() {
  echo "::error title=release-beta-gate indeterminate::$1 — keeping release PR #${PR} out of auto-merge"
  disable_auto
  exit 1
}

PARENT="$(gh api "repos/${REPO}/commits/${HEAD_SHA}" --jq '.parents[0].sha // empty' 2>&1)" ||
  indeterminate "could not read release commit ${HEAD_SHA}: ${PARENT}"
[ -n "$PARENT" ] || indeterminate "release commit ${HEAD_SHA} has no parent"

CODE_SHA="$(gh api "repos/${REPO}/commits?sha=${PARENT}&path=${CODE_PATH}&per_page=1" \
  --jq '.[0].sha // empty' 2>&1)" ||
  indeterminate "could not find the last ${CODE_PATH} commit at ${PARENT}: ${CODE_SHA}"
[ -n "$CODE_SHA" ] || indeterminate "no commit at or before ${PARENT} touches ${CODE_PATH}"

echo "Release PR #${PR} releases ${PARENT}; its ${CODE_PATH} code is ${CODE_SHA}."

RUN_ID=""
CONCLUSION=""
WAITING_ON=""

# decide <run id>: read BETA_JOB in that run. Returns 0 when it finished
# success or failure (setting RUN_ID and CONCLUSION), 1 when it decided
# nothing: cancelled, skipped, absent, or still running (noted in WAITING_ON).
decide() {
  local jobs row status conclusion
  # TSV + awk rather than interpolating BETA_JOB into a jq filter.
  jobs="$(gh api "repos/${REPO}/actions/runs/$1/jobs?per_page=100" \
    --jq '.jobs[] | "\(.name)\t\(.status)\t\(.conclusion // "")"' 2>&1)" ||
    indeterminate "could not read jobs for run $1: ${jobs}"
  row="$(printf '%s\n' "$jobs" | awk -F'\t' -v want="$BETA_JOB" '$1 == want { print; exit }')"
  status="$(printf '%s' "$row" | cut -f2)"
  conclusion="$(printf '%s' "$row" | cut -f3)"
  if [ "$status" = "completed" ]; then
    case "$conclusion" in
      success | failure | timed_out | action_required | startup_failure)
        RUN_ID="$1"
        CONCLUSION="$conclusion"
        return 0
        ;;
    esac
  elif [ -n "$row" ]; then
    WAITING_ON="${WAITING_ON:-$1}"
  fi
  return 1
}

# 1. The newest push runs, newest first, back to the code commit's own run.
#    Coalescing only ever hands a change to the next run or two, so 20 is
#    plenty; an older code commit is found by sha below.
runs="$(gh api "repos/${REPO}/actions/workflows/${WORKFLOW}/runs?event=push&branch=main&per_page=20" \
  --jq '.workflow_runs[] | "\(.id)\t\(.head_sha)"' 2>&1)" ||
  indeterminate "could not list push ${WORKFLOW} runs: ${runs}"
# Read after the runs, so no listed run is newer than this answer. When main
# has no CODE_PATH change after CODE_SHA, every run newer than the code
# commit's own built the same code, and no run needs its own lookup.
LATEST_CODE="$(gh api "repos/${REPO}/commits?sha=main&path=${CODE_PATH}&per_page=1" \
  --jq '.[0].sha // empty' 2>&1)" ||
  indeterminate "could not find the last ${CODE_PATH} commit on main: ${LATEST_CODE}"
SEEN_OWN=""
while IFS=$'\t' read -r id sha; do
  [ -n "$id" ] || continue
  if [ "$sha" = "$CODE_SHA" ]; then
    SEEN_OWN=1
  elif [ "$LATEST_CODE" != "$CODE_SHA" ]; then
    # main has moved past this release PR's code: only runs whose commit still
    # has it count (a newer change's run is not the code this release ships).
    at="$(gh api "repos/${REPO}/commits?sha=${sha}&path=${CODE_PATH}&per_page=1" \
      --jq '.[0].sha // empty' 2>&1)" ||
      indeterminate "could not find the last ${CODE_PATH} commit at ${sha}: ${at}"
    [ "$at" = "$CODE_SHA" ] || continue
  fi
  decide "$id" && break
  # Nothing older than the code commit's own run built this code.
  [ -z "$SEEN_OWN" ] || break
done <<<"$runs"

# 2. A release PR can outlive that window (held, or waiting on CI while main
#    moves on). Its code commit's own runs are always found by sha.
if [ -z "$CONCLUSION" ] && [ -z "$SEEN_OWN" ]; then
  own="$(gh api "repos/${REPO}/actions/workflows/${WORKFLOW}/runs?head_sha=${CODE_SHA}&event=push&per_page=10" \
    --jq '.workflow_runs[].id' 2>&1)" ||
    indeterminate "could not list push ${WORKFLOW} runs for ${CODE_SHA}: ${own}"
  for id in $own; do
    decide "$id" && break
  done
fi

case "$CONCLUSION" in
  success)
    echo "${BETA_JOB} succeeded for ${CODE_SHA} in run ${RUN_ID}."
    if [ "$IS_DRAFT" = "true" ]; then
      echo "Release PR #${PR} is a draft — leaving it for a maintainer."
      exit 0
    fi
    if printf '%s' "$LABELS" | tr ',' '\n' | grep -qx "$HOLD_LABEL"; then
      gh pr edit "$PR" --repo "$REPO" --remove-label "$HOLD_LABEL" || true
    fi
    if [ "$AUTO_ON" = "true" ]; then
      echo "Auto-merge already enabled on #${PR}."
    else
      echo "Enabling auto-merge on #${PR}; the merge queue merges it on green CI."
      gh pr merge "$PR" --repo "$REPO" --squash --auto || {
        echo "::error title=auto-merge not enabled::could not enable auto-merge on #${PR}; re-run this workflow or merge it by hand"
        exit 1
      }
    fi
    ;;
  failure | cancelled | timed_out | action_required | startup_failure)
    echo "::warning title=release PR held::${BETA_JOB} concluded '${CONCLUSION}' for ${CODE_SHA} — holding release PR #${PR}"
    gh pr edit "$PR" --repo "$REPO" --add-label "$HOLD_LABEL" || true
    disable_auto
    # One comment per failed commit, however many times this re-evaluates it.
    marker="<!-- release-beta-gate:${CODE_SHA} -->"
    if ! gh pr view "$PR" --repo "$REPO" --json comments --jq '.comments[].body' 2>/dev/null |
         grep -qF "$marker"; then
      gh pr comment "$PR" --repo "$REPO" --body "${marker}
Held out of auto-merge: \`${BETA_JOB}\` concluded **${CONCLUSION}** for ${CODE_SHA} in [run ${RUN_ID}](https://github.com/${REPO}/actions/runs/${RUN_ID}).

That rung builds the same artifact the release would attach, so this release would publish nothing. Fix it on \`main\`; release-please then rebuilds this PR on the fix, and it is released automatically once \`${BETA_JOB}\` succeeds there." || true
    fi
    ;;
  *)
    if [ -n "$WAITING_ON" ]; then
      echo "${BETA_JOB} for ${CODE_SHA} is still running in run ${WAITING_ON} — waiting."
    else
      echo "No push ${WORKFLOW} run has finished ${BETA_JOB} for ${CODE_SHA} yet — waiting."
    fi
    disable_auto
    ;;
esac
exit 0
