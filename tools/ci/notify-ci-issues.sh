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

# notify-ci-issues.sh — poll for stuck approvals and main-branch failures,
# push an ntfy notification for each. See notify-ci-issues.yaml's header for
# why this is polling rather than event-driven, and why there is no
# persistent dedup state.
#
# Three independent checks, each tolerant of the others' failures (no `-e`:
# one bad iteration must not stop the rest):
#   1. runs `waiting` on a required-reviewer deployment-environment approval
#   2. runs `action_required`, blocked on the "Approve and run" gate, grouped
#      by head branch (that gate blocks every workflow on a ref at once)
#   3. push runs on main that concluded `failure`
#
# Environment:
#   REPO             owner/repo
#   GH_TOKEN         token gh authenticates as (needs actions: read)
#   NTFY_PASSWORD    ntfy basic-auth password for the github-actions user
#   CUTOFF_MINUTES   how far back "recently updated" reaches (default: 20,
#                    comfortably wider than the 5-minute schedule since
#                    schedule triggers are best-effort and can slip)
#
# Exit: always 0. A failed ntfy push is logged to stderr as a WARN and does
# not fail the run — silence on a real stuck approval is the failure mode
# this exists to prevent, not a missed push.

set -uo pipefail  # no -e: one bad iteration must not stop the rest

REPO="${REPO:?REPO must be set (owner/repo)}"
CUTOFF_MINUTES="${CUTOFF_MINUTES:-20}"

cutoff=$(date -u -d "${CUTOFF_MINUTES} minutes ago" +%Y-%m-%dT%H:%M:%SZ)

notify() {
  local title="$1" message="$2" priority="$3" tags="$4" url="$5"
  local body
  body=$(jq -n \
    --arg title "$title" --arg message "$message" \
    --argjson priority "$priority" --argjson tags "$tags" --arg click "$url" \
    '{topic:"vitruvian-alerts", title:$title, message:$message, priority:$priority, tags:$tags, click:$click}')
  if ! curl -fsS -u "github-actions:${NTFY_PASSWORD}" \
      -H "Content-Type: application/json" \
      -H "User-Agent: vitruvian-ci-notify/1.0" \
      -X POST https://ntfy.ipv1337.dev -d "$body" >/dev/null; then
    echo "WARN: ntfy push failed for: $title" >&2
  fi
}

# shellcheck disable=SC2016 # $cutoff is jq's --arg binding, not a shell var
recent_filter='.workflow_runs[] | select(.updated_at >= $cutoff) | [.name, .html_url] | @tsv'

# gh api's -q/--jq takes only a filter string, with no equivalent of jq's own
# --arg for binding variables into it — pipe to a separate jq instead, which
# does support --arg. --paginate with no --slurp emits each page as its own
# top-level JSON object, back to back; jq processes a stream of top-level
# values by default, so this still applies the filter once per page correctly.
echo "Checking for runs waiting on approval, updated since ${cutoff}..."
gh api "repos/${REPO}/actions/runs?status=waiting&per_page=50" --paginate |
jq -r --arg cutoff "$cutoff" "$recent_filter" |
while IFS=$'\t' read -r name url; do
  echo "  -> waiting: $name ($url)"
  notify "[ci] approval needed: ${name}" \
    "Workflow run is waiting on a required-reviewer approval. ${url}" \
    4 '["hourglass_flowing_sand","ci"]' "$url"
done

# `waiting` (above) is ONLY the deployment-environment reviewer gate. A
# workflow run blocked on the *other* GitHub approval gate -- the "Approve
# and run" button on a run GitHub refuses to start on its own -- reports
# `action_required` instead, and the poll above is blind to it. Found live on
# 2026-08-05: buzz digest PR #1409 had all 8 of its check runs parked in
# `action_required`, leaving the PR mergeStateStatus=BLOCKED with 14/15
# required contexts absent, and this workflow said nothing for hours. Same
# class of silence the `waiting` poll exists to prevent, so it gets the same
# treatment. Grouped by head branch, unlike the two per-run polls either side
# of this one: this gate blocks EVERY workflow on the ref at once (all 8 on
# #1409), so a per-run push would mean 8 phone alerts for a single click.
# `jq -s` slurps --paginate's back-to-back page objects into one array, which
# is what group_by needs; the click-through is the first run of the group,
# whose page carries the approval button for the whole ref.
echo "Checking for runs needing approval to start, updated since ${cutoff}..."
gh api "repos/${REPO}/actions/runs?status=action_required&per_page=50" --paginate |
jq -s -r --arg cutoff "$cutoff" '
  [.[].workflow_runs[] | select(.updated_at >= $cutoff)]
  | group_by(.head_branch)[]
  | [.[0].head_branch, (length | tostring), .[0].html_url] | @tsv
' |
while IFS=$'\t' read -r branch count url; do
  echo "  -> action_required: ${count} run(s) on ${branch} ($url)"
  notify "[ci] approval needed to start: ${branch}" \
    "${count} workflow run(s) on ${branch} will not start until approved ('Approve and run'). Required checks stay absent and the PR stays blocked until then. ${url}" \
    4 '["hourglass_flowing_sand","ci"]' "$url"
done

echo "Checking for failures on main, updated since ${cutoff}..."
gh api "repos/${REPO}/actions/runs?branch=main&event=push&status=failure&per_page=20" --paginate |
jq -r --arg cutoff "$cutoff" "$recent_filter" |
while IFS=$'\t' read -r name url; do
  echo "  -> failed on main: $name ($url)"
  notify "[ci] main broken: ${name}" \
    "Failed on main after landing. ${url}" \
    5 '["red_circle","ci"]' "$url"
done
