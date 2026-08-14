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

# release-hold.sh — hold or release this component's open release PR based on
# the conclusion of its development deploy job. See release-hold.yaml's header
# for the full rationale (the fast-feedback half of the dev->nonprod
# interlock; WHY BOTH, and why the label alone can't stop auto-merge).
#
# Environment:
#   REPO            owner/repo
#   RUN_ID          the workflow_run id that triggered this evaluation
#   DEV_JOB         exact job name proving the development deploy, e.g.
#                   "deploy-dev / deploy"
#   COMPONENT       release-please component name, e.g. tabula-api
#   SOURCE          the deploy workflow this matrix entry is FOR (e.g.
#                   tabula-deploy); optional — when set together with
#                   TRIGGERED_BY, entries for the other deploy workflow are
#                   skipped as a no-op.
#   TRIGGERED_BY    the deploy workflow that actually fired
#                   (github.event.workflow_run.name); optional, see SOURCE.
#   GH_TOKEN        token gh authenticates as (needs pull-requests: write to
#                   edit/merge/comment, actions: read to view the run's jobs)
#
# Exit: always 0 — this script informs and adjusts PR state, it never fails
# the calling job. Genuine lookup failures are surfaced as ::warning:: and
# leave the release PR untouched rather than acting on missing information.

set -uo pipefail

REPO="${REPO:?REPO must be set (owner/repo)}"
RUN_ID="${RUN_ID:?RUN_ID must be set}"
DEV_JOB="${DEV_JOB:?DEV_JOB must be set}"
COMPONENT="${COMPONENT:?COMPONENT must be set}"
SOURCE="${SOURCE:-}"
TRIGGERED_BY="${TRIGGERED_BY:-}"

# One matrix covers every app, so drop the entries that belong to the OTHER
# deploy workflow. Filtered here rather than in a job-level `if:` to avoid
# depending on whether the matrix context is available during job-level
# condition evaluation.
if [ -n "$SOURCE" ] && [ -n "$TRIGGERED_BY" ] && [ "$SOURCE" != "$TRIGGERED_BY" ]; then
  echo "Triggered by '${TRIGGERED_BY}', this entry is for '${SOURCE}' — nothing to do."
  exit 0
fi

# release-please's branch name is deterministic and per-component (verified on
# the real PRs, e.g. release-please--branches--main--components--tabula-api),
# so this targets exactly one PR and can never touch a human's branch.
BRANCH="release-please--branches--main--components--${COMPONENT}"

# Bug fix: the original inline step piped stderr to /dev/null and never
# checked gh's exit status here, unlike the `gh run view` call a few lines
# below which correctly checks `$?`. A transient API failure on THIS call
# produced the exact same empty result as "genuinely no open release PR",
# silently skipping the hold with no error surfaced anywhere. Capture stderr
# and check the exit status explicitly, matching the already-correct pattern
# used for the jobs lookup below.
pr_lookup="$(gh pr list --repo "$REPO" --head "$BRANCH" --state open \
  --json number --jq '.[0].number // empty' 2>&1)"
pr_rc=$?
if [ "$pr_rc" -ne 0 ]; then
  echo "::warning title=release-hold indeterminate::could not list open release PRs on ${BRANCH}: ${pr_lookup} — leaving any hold/release untouched"
  exit 0
fi
PR="$pr_lookup"
if [ -z "$PR" ]; then
  echo "No open release PR on ${BRANCH} — nothing to hold or release."
  exit 0
fi

# Read the development job's conclusion off the run that triggered us. TSV +
# awk rather than interpolating DEV_JOB into a jq filter.
jobs="$(gh run view "$RUN_ID" --repo "$REPO" --json jobs \
  --jq '.jobs[] | "\(.name)\t\(.conclusion)"' 2>&1)"
# shellcheck disable=SC2181  # deliberately indirect: this is the pre-existing
# "already-correct" pattern the pr_rc check above was rewritten to MATCH, kept
# verbatim rather than restyled to a pure extraction's benefit.
if [ $? -ne 0 ]; then
  echo "::warning title=release-hold indeterminate::could not read jobs for run ${RUN_ID}: ${jobs} — leaving release PR #${PR} untouched"
  exit 0
fi

CONCLUSION="$(printf '%s\n' "$jobs" | awk -F'\t' -v want="$DEV_JOB" \
  '$1 == want { print $2; exit }')"

if [ -z "$CONCLUSION" ]; then
  echo "Run ${RUN_ID} has no '${DEV_JOB}' job (nothing deployable changed) — leaving release PR #${PR} untouched."
  exit 0
fi

echo "Development job '${DEV_JOB}' concluded '${CONCLUSION}' in run ${RUN_ID}; release PR is #${PR}."

case "$CONCLUSION" in
  success | skipped)
    # Clear a hold THIS workflow previously applied. Re-enabling auto-merge is
    # idempotent and is what actually releases the PR; removing the label
    # alone would not (see the header note).
    if gh pr view "$PR" --repo "$REPO" --json labels \
         --jq '.labels[].name' 2>/dev/null | grep -qx 'do-not-automerge'; then
      echo "Development is green again — releasing the hold on #${PR}."
      gh pr edit "$PR" --repo "$REPO" --remove-label do-not-automerge || true
      gh pr merge "$PR" --repo "$REPO" --squash --auto || \
        echo "::warning title=auto-merge not re-enabled::could not re-enable auto-merge on #${PR}; merge it manually or re-run this workflow"
    else
      echo "No hold in place on #${PR}; nothing to do."
    fi
    ;;
  failure | cancelled | timed_out | action_required | startup_failure)
    echo "::warning title=release PR held::${COMPONENT}'s development deploy concluded '${CONCLUSION}' — holding release PR #${PR} out of auto-merge"
    gh pr edit "$PR" --repo "$REPO" --add-label do-not-automerge || true
    # THE load-bearing call: the label documents the hold, this enforces it.
    gh pr merge "$PR" --repo "$REPO" --disable-auto || \
      echo "::warning title=auto-merge still enabled::could not disable auto-merge on #${PR} — it may merge despite the hold label"
    gh pr comment "$PR" --repo "$REPO" --body \
      "Held out of auto-merge: \`${COMPONENT}\`'s development deploy concluded **${CONCLUSION}** in [run ${RUN_ID}](https://github.com/${REPO}/actions/runs/${RUN_ID}).

Merging this release would promote an artifact whose development deploy is red, and nonproduction has no reviewer to catch it. This PR is released automatically once development is green again." || true
    ;;
  *)
    echo "Unrecognised conclusion '${CONCLUSION}' — leaving #${PR} untouched."
    ;;
esac
