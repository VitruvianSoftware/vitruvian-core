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

# Did this work actually land on main?
#
#   bazel run //tools/landed -- 1205                 # a PR number
#   bazel run //tools/landed -- claude/my-branch     # a branch
#   bazel run //tools/landed -- da6612ad             # a local commit
#
# WHY THIS EXISTS, and why the obvious one-liner is wrong:
#
#   git merge-base --is-ancestor <branch-sha> origin/main
#
# always answers "no" in this repo, for every PR that ever merged. `main` is
# SQUASH-ONLY -- enforced, not conventional: the repo_config ruleset pins
# AllowedMergeMethods to ["squash"]. A squash REWRITES the branch's commits into
# one new commit with a new SHA and main as its parent, so the SHA you pushed is
# never an ancestor of main. Neither would rebase-merge help; only a true merge
# commit preserves the original SHAs, and that is exactly the messy history the
# squash-only rule exists to prevent.
#
# The failure mode is nasty because it is a FALSE NEGATIVE on the safe-looking
# side: the check says "not merged" about work that is merged. On 2026-07-25 it
# reported three landed PRs (#1200, #1204, #1205) as missing from main, moments
# before those branches were deleted -- i.e. it argued for treating real work as
# unmerged. A check that fails toward "you still have unsaved work" is one thing;
# this one fails toward "your verification is broken and you cannot tell".
#
# THE FIX IS NOT A DIFFERENT SHA COMPARISON, IT IS A DIFFERENT IDENTITY. A branch
# SHA does not survive a squash. The PR NUMBER does, and GitHub exposes two
# handles that cross the boundary:
#   1. `gh pr view N --json mergeCommit` -> the authoritative squashed SHA, which
#      IS an ancestor of main and can be verified locally.
#   2. the "(#N)" suffix GitHub appends to every squash title, so
#      `git log --grep "(#N)"` finds it with no API call.
# This script resolves whatever you hand it down to (1), then verifies locally.
#
# Verifying the squashed SHA rather than trusting the PR's MERGED state is
# deliberate: "MERGED" is GitHub's view, and the question being asked is about
# THIS checkout's origin/main. Those differ whenever the fetch is stale, which is
# precisely when someone is confused enough to be running this.

set -uo pipefail

REPO="${LANDED_REPO:-VitruvianSoftware/vitruvian-core}"
BASE="${LANDED_BASE:-origin/main}"

info() { printf '\033[36m→\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
die()  { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

cd "${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}" ||
  die "cannot find a workspace to run in"

ref="${1:-}"
[ -n "${ref}" ] || die "usage: landed <pr-number|branch|commit-sha>

   Answers whether that work is on ${BASE}, correctly under squash-merge."

command -v gh >/dev/null 2>&1 || die "gh not on PATH (needed to resolve the PR)."

# ── Resolve whatever we were given down to a PR number. ──────────────────────
# Order matters: a branch can be all-hex and a short SHA can look like a branch,
# so try the cheap unambiguous cases first and fall through.
pr=""
case "${ref}" in
  '#'*) pr="${ref#\#}" ;;
  *[!0-9]*) : ;;   # not purely numeric -- resolved below
  *) pr="${ref}" ;; # purely numeric -> a PR number
esac

if [ -z "${pr}" ]; then
  # A branch name? --state all so a merged (and auto-deleted) branch still resolves.
  pr="$(gh pr list --repo "${REPO}" --head "${ref}" --state all \
        --json number,createdAt -q 'sort_by(.createdAt)|last|.number' 2>/dev/null)"
fi

if [ -z "${pr}" ] || [ "${pr}" = "null" ]; then
  # A commit SHA, then. Only works once GitHub has seen the commit -- a purely
  # local commit resolves to nothing, which is itself the answer.
  pr="$(gh api "repos/${REPO}/commits/${ref}/pulls" \
        -q 'map(select(.merged_at != null))|sort_by(.merged_at)|last|.number' 2>/dev/null)"
fi

[ -n "${pr}" ] && [ "${pr}" != "null" ] ||
  die "could not resolve '${ref}' to a pull request.

   If it is a LOCAL-ONLY commit, that is the answer: it was never pushed, so it
   cannot have landed. If it is a branch, it may never have had a PR opened."

# ── Ask GitHub for the squashed commit, then verify it locally. ──────────────
read -r state squashed < <(gh pr view "${pr}" --repo "${REPO}" \
  --json state,mergeCommit -q '"\(.state) \(.mergeCommit.oid // "-")"' 2>/dev/null)

[ -n "${state:-}" ] || die "gh could not read PR #${pr} in ${REPO}."

case "${state}" in
  MERGED) : ;;
  *) die "PR #${pr} is ${state}, not MERGED -- this work is NOT on ${BASE}.

   Do not push follow-up commits to a merged PR's branch either: the repo
   auto-deletes branches on merge, so a push silently re-creates a dangling one." ;;
esac

[ "${squashed}" != "-" ] ||
  die "PR #${pr} reports MERGED but exposes no merge commit, so it cannot be
   verified against ${BASE}. Check it by content instead."

git fetch origin "${BASE#origin/}" -q 2>/dev/null || true

if ! git cat-file -e "${squashed}^{commit}" 2>/dev/null; then
  die "PR #${pr} squashed to ${squashed:0:8}, which this checkout does not have.
   Fetch and re-run; do not conclude anything from a stale ${BASE}."
fi

if git merge-base --is-ancestor "${squashed}" "${BASE}" 2>/dev/null; then
  ok "PR #${pr} is on ${BASE} as ${squashed:0:8} (squashed)."
  info "$(git log -1 --format='%s' "${squashed}")"
  exit 0
fi

die "PR #${pr} says MERGED and squashed to ${squashed:0:8}, but that commit is
   NOT an ancestor of ${BASE} in this checkout. Either ${BASE} is stale, or it
   was merged into a different base branch. Do not report this as landed."
