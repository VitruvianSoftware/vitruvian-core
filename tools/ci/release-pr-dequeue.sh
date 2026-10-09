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

# release-pr-dequeue.sh — take a component's release PR out of the merge queue
# when main has just gained a change that PR does not list, so release-please
# can refresh it. Run BEFORE release-please in the component's release workflow.
#
# Why: GitHub refuses a branch update while the PR is in the merge queue.
# release-please then fails ("Error updating ref heads/release-please--...") and
# the queued PR merges as it was: the release ships the new change, but its
# changelog and version bump were worked out without it (issue #2938; a feature
# went out as a patch in vitruvian 3.33.1, and 3.34.4 missed two fixes).
#
# Out of the queue, release-please rebuilds the PR on the new commit, and
# whatever queued it before queues it again: for vitruvian that is
# release-beta-gate.yaml, once the beta DMG exists for the new code.
#
# Environment:
#   REPO        owner/repo
#   COMPONENT   release-please component name, e.g. vitruvian
#   CODE_PATH   the component's directory, e.g. apps/desktop/vitruvian
#   MAIN_SHA    the main commit this release run is for (github.sha)
#   GH_TOKEN    token gh authenticates as (pull-requests: write)
#
# The PR is left queued when it already releases MAIN_SHA's CODE_PATH code: a
# release-please PR is ONE commit on top of the main commit it releases, so
# that commit's first parent is what it lists. Same newest CODE_PATH commit at
# both means nothing to add, and a dequeue would only delay the release.
#
# Exit: always 0. A failed lookup or dequeue is a ::warning:: and the PR is left
# alone; release-please runs next and fails loudly if it still cannot update
# the branch, so nothing is hidden.

set -uo pipefail

REPO="${REPO:?REPO must be set (owner/repo)}"
COMPONENT="${COMPONENT:?COMPONENT must be set}"
CODE_PATH="${CODE_PATH:?CODE_PATH must be set}"
MAIN_SHA="${MAIN_SHA:?MAIN_SHA must be set}"

# release-please's branch name is deterministic and per-component, so this
# targets exactly one PR and can never touch a human's branch.
BRANCH="release-please--branches--main--components--${COMPONENT}"

skip() {
  echo "::warning title=release PR left in the queue::$1"
  exit 0
}

# A fork can name its branch the same; only the in-repo release PR counts.
# shellcheck disable=SC2016 # $owner/$name/$branch are GraphQL variables
pr_row="$(gh api graphql \
  -f owner="${REPO%%/*}" -f name="${REPO##*/}" -f branch="$BRANCH" \
  -f query='query($owner:String!,$name:String!,$branch:String!){repository(owner:$owner,name:$name){pullRequests(headRefName:$branch,states:OPEN,first:10){nodes{number id headRefOid isCrossRepository isInMergeQueue}}}}' \
  --jq '.data.repository.pullRequests.nodes | map(select(.isCrossRepository | not)) | .[0] // empty | "\(.number)\t\(.id)\t\(.headRefOid)\t\(.isInMergeQueue)"' 2>&1)" ||
  skip "could not list open release PRs on ${BRANCH}: ${pr_row}"
if [ -z "$pr_row" ]; then
  echo "No open release PR on ${BRANCH} — nothing to dequeue."
  exit 0
fi
IFS=$'\t' read -r PR PR_ID HEAD_SHA QUEUED <<<"$pr_row"
if [ "$QUEUED" != "true" ]; then
  echo "Release PR #${PR} is not in the merge queue — release-please can update it."
  exit 0
fi

PARENT="$(gh api "repos/${REPO}/commits/${HEAD_SHA}" --jq '.parents[0].sha // empty' 2>&1)" ||
  skip "could not read release commit ${HEAD_SHA} of #${PR}: ${PARENT}"
[ -n "$PARENT" ] || skip "release commit ${HEAD_SHA} of #${PR} has no parent"

code_at() { # <commit>: the newest commit at or before it that touched CODE_PATH
  gh api "repos/${REPO}/commits?sha=$1&path=${CODE_PATH}&per_page=1" --jq '.[0].sha // empty' 2>&1
}
LISTED="$(code_at "$PARENT")" ||
  skip "could not find the last ${CODE_PATH} commit at ${PARENT}: ${LISTED}"
LATEST="$(code_at "$MAIN_SHA")" ||
  skip "could not find the last ${CODE_PATH} commit at ${MAIN_SHA}: ${LATEST}"
[ -n "$LISTED" ] && [ -n "$LATEST" ] ||
  skip "no ${CODE_PATH} commit found at ${PARENT} or ${MAIN_SHA}"

if [ "$LISTED" = "$LATEST" ]; then
  echo "Queued release PR #${PR} already releases ${LATEST} — leaving it in the queue."
  exit 0
fi

echo "Queued release PR #${PR} releases ${LISTED}, but main is at ${LATEST} — taking it out of the merge queue so release-please can refresh it."
# shellcheck disable=SC2016 # $id is a GraphQL variable
out="$(gh api graphql -f id="$PR_ID" \
  -f query='mutation($id:ID!){dequeuePullRequest(input:{id:$id}){clientMutationId}}' 2>&1)" ||
  skip "could not dequeue #${PR}: ${out}"
echo "Release PR #${PR} is out of the merge queue."
exit 0
