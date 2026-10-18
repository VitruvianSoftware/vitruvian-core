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

# Puts a website pull request that a workflow opened into the merge queue, so
# it merges on green checks without a person. Used by catalog-publish and
# site-sync-downloads, which push one commit to a branch of their own and open
# or update a pull request from it. Before this, those pull requests sat open
# for hours with green checks (#3445, #3460, #3468, #3473): nothing armed them.
#
#   site-pr-automerge.sh disarm --branch <branch>
#       Before the push. Turns auto-merge off on the open pull request from
#       <branch>, if there is one and it is on, so an arming made for an
#       earlier commit does not carry the commit about to be pushed. The same
#       step catalog-bump takes before it pushes.
#
#   site-pr-automerge.sh arm --branch <branch> --sha <sha>
#       After the push. Arms auto-merge (squash, the only method main allows)
#       on the open pull request from <branch>, at <sha> only
#       (--match-head-commit): GitHub refuses when the head is no longer the
#       commit this run pushed.
#
# It does not arm, and turns auto-merge off if it is on, when:
#   - the pull request is held: labelled do-not-automerge (a person's hold,
#     as release-pr-automerge, release-hold and release-beta-gate read it) or
#     needs-human (catalog-check's hold, catalog/bump.py HOLDS), or a draft.
#     It never adds or removes a label: a hold is a person's to lift.
#   - its head is not <sha>: someone pushed after this run. That commit is
#     theirs to merge.
# Each of those ends 0 with a line in the job summary.
#
# A failure to read the pull request or to arm it ends 1, with a warning in the
# job summary and an ::error annotation, as catalog-check's bump-automerge and
# release-beta-gate do: a pull request that is not armed is the stall this
# exists to end, so it must not pass quietly.
#
# Env: GH_TOKEN (the App token; arming needs contents: write and
# pull-requests: write), REPO (owner/name), GITHUB_STEP_SUMMARY (optional).
# Test: //tools/ci:site_pr_automerge_test.

set -uo pipefail

usage() {
  echo "usage: $0 disarm --branch <branch> | arm --branch <branch> --sha <sha>" >&2
  exit 2
}

mode="${1:-}"
[ "$#" -gt 0 ] && shift
branch=""
sha=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --branch) branch="${2:-}"; shift 2 || usage ;;
    --sha) sha="${2:-}"; shift 2 || usage ;;
    *) usage ;;
  esac
done
case "$mode" in
  disarm) [ -n "$branch" ] || usage ;;
  arm) [ -n "$branch" ] && [ -n "$sha" ] || usage ;;
  *) usage ;;
esac
if [ -z "${REPO:-}" ]; then
  echo "REPO (owner/name) is not set" >&2
  exit 2
fi

summary="${GITHUB_STEP_SUMMARY:-/dev/null}"

# A line for the log and the job summary.
say() {
  printf '%s\n' "$1"
  printf '%s\n\n' "$1" >>"$summary"
}

# Not armed, and it should have been: a warning in the summary, an error
# annotation, and a failed step.
fail() {
  echo "::error title=auto-merge not armed::$1"
  printf '> [!WARNING]\n> **Auto-merge is not armed.** %s\n\n' "$1" >>"$summary"
  exit 1
}

open_pr() {
  gh pr list --repo "$REPO" --head "$branch" --base main --state open \
    --json number --jq '.[0].number // empty'
}

# "<armed> <draft> <head> <hold labels, comma-separated>"
pr_state() {
  gh pr view "$1" --repo "$REPO" --json autoMergeRequest,isDraft,headRefOid,labels \
    --jq '[(.autoMergeRequest != null), .isDraft, .headRefOid,
           ([.labels[].name | select(. == "do-not-automerge" or . == "needs-human")] | join(","))]
          | map(tostring) | join(" ")'
}

disarm() { # <number> <why>
  if gh pr merge "$1" --repo "$REPO" --disable-auto; then
    say "Turned auto-merge off on #$1: $2."
  else
    echo "::warning title=auto-merge still on::could not turn auto-merge off on #$1 ($2)"
    printf '> [!WARNING]\n> Could not turn auto-merge off on #%s (%s).\n\n' "$1" "$2" >>"$summary"
    return 1
  fi
}

if [ "$mode" = "disarm" ]; then
  # A failure here fails the step before the push, as catalog-bump's does:
  # the next run tries again, and nothing rides on a stale arming meanwhile.
  if ! number="$(open_pr)"; then
    echo "::error::could not look up the open pull request from $branch"
    exit 1
  fi
  if [ -z "$number" ]; then
    echo "No open pull request from $branch yet."
    exit 0
  fi
  if ! armed="$(gh pr view "$number" --repo "$REPO" --json autoMergeRequest --jq '.autoMergeRequest != null')"; then
    echo "::error::could not read #$number"
    exit 1
  fi
  if [ "$armed" = "true" ]; then
    disarm "$number" "this run is about to push a new commit; it is armed again at that commit only" || exit 1
  else
    echo "Auto-merge is off on #$number."
  fi
  exit 0
fi

if ! number="$(open_pr)"; then
  fail "could not look up the open pull request from \`$branch\`."
fi
[ -n "$number" ] || fail "no open pull request from \`$branch\`, though this run just pushed it."

if ! state="$(pr_state "$number")"; then
  fail "could not read #$number."
fi
read -r armed draft head held <<<"$state"
held="${held:-}"

if [ -n "$held" ] || [ "$draft" = "true" ]; then
  why="it is held"
  [ -n "$held" ] && why="$why (${held//,/, })"
  [ "$draft" = "true" ] && why="$why (a draft)"
  if [ "$armed" = "true" ]; then
    disarm "$number" "$why" || exit 1
  fi
  say "#$number is not armed: $why. Lift the hold and arm it by hand: \`gh pr merge $number --squash --auto\`."
  exit 0
fi

if [ "$head" != "$sha" ]; then
  if [ "$armed" = "true" ]; then
    disarm "$number" "its head moved to $head after this run pushed $sha" || exit 1
  fi
  echo "::warning title=auto-merge not armed::#$number's head is $head, not $sha: someone pushed after this run. Not arming a commit this run did not write."
  say "#$number is not armed: its head is \`$head\`, not \`$sha\`, which this run pushed."
  exit 0
fi

if [ "$armed" = "true" ]; then
  say "Auto-merge is already on for #$number."
  exit 0
fi

if ! gh pr merge "$number" --repo "$REPO" --squash --auto --match-head-commit "$sha"; then
  fail "\`gh pr merge $number --squash --auto --match-head-commit $sha\` failed. Re-run this workflow, or arm it by hand."
fi
say "Armed auto-merge on #$number at \`$sha\`: the merge queue merges it once its checks pass."
