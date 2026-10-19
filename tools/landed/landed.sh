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
#   bazel run //tools/landed -- --branch my/branch   # is it SAFE TO DELETE this local branch?
#   bazel run //tools/landed -- --remote-branch my/branch   # ...this branch on origin?
#
# --branch is the gate //tools/worktree uses before it deletes a branch. The
# plain modes answer "did PR #N land"; --branch answers the stricter question
# "is every commit on this LOCAL branch already on main", so a branch that had
# its PR merged and then grew more unpushed commits is NOT safe. See gate_branch.
# --remote-branch asks the same of the branch as it is on origin (fetched
# first), and is the gate `//tools/agent-app -- branch-delete` uses.
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

fetch_base() {
  # LANDED_NO_FETCH=1 lets a caller that checks many branches fetch once.
  [ "${LANDED_NO_FETCH:-0}" = "1" ] || git fetch origin "${BASE#origin/}" -q 2>/dev/null || true
}

# extras_on_base <head> <tip>: does every commit between a merged PR's head and
# the branch's tip add nothing BASE lacks? Branches grow such commits after
# their PR merges: a merge from main, an empty "trigger release" commit, a sync
# job re-pushing what main already has. Each commit not on BASE must be one of:
#   - empty (its tree is its parent's),
#   - a merge with no hand-made resolution (its tree is what `git merge-tree`
#     makes of its two parents); whatever it brings in is checked on its own,
#     because those commits are in the same range,
#   - a patch BASE already has (`git cherry` marks it "-").
# Anything else, or a tip that does not descend from the head, fails.
extras_on_base() {
  local head="$1" tip="$2" c parents
  git merge-base --is-ancestor "${head}" "${tip}" 2>/dev/null || return 1
  while read -r c; do
    read -r -a parents <<<"$(git rev-list --parents -n 1 "${c}")"
    case "${#parents[@]}" in
      2)
        [ "$(git rev-parse "${c}^{tree}")" = "$(git rev-parse "${c}^^{tree}")" ] && continue
        git cherry "${BASE}" "${c}" "${c}^" 2>/dev/null | grep -q '^-' || return 1 ;;
      3)
        [ "$(git merge-tree --write-tree "${parents[1]}" "${parents[2]}" 2>/dev/null | head -1)" = \
          "$(git rev-parse "${c}^{tree}")" ] || return 1 ;;
      *) return 1 ;;
    esac
  done < <(git rev-list "${tip}" "^${head}" "^${BASE}")
}

# ── --branch / --remote-branch: is every commit on this branch already on BASE?
# Passes (exit 0) on any ONE of four independent proofs, cheapest first:
#   1. the branch tip is an ancestor of BASE -- nothing of its own to lose.
#   2. CONTENT: merging the branch into BASE changes nothing (`git merge-tree`
#      yields BASE's own tree). This is what survives a squash: the SHAs differ
#      but every line the branch would add is already there. No network needed.
#   3. PR: the branch's PR is MERGED, its squashed commit is on BASE, AND the
#      tip is the PR's head (or behind it). Covers a landed branch whose
#      lines main has since changed again, which makes (2) see a difference.
#   4. PR, then more: as (3), but the tip is past the PR's head, and every
#      commit after the head adds nothing BASE lacks (extras_on_base).
# Anything else is "not landed" (exit 1), and that includes "could not tell":
# this gate guards a deletion, so an unknown must fail toward keeping the work.
# gate_branch <name> <tip-sha> <where>, where says which copy ("the local
# branch", "the branch on origin") for the messages.
gate_branch() {
  local br="$1" tip="$2" where="$3" base_tree merged pr_line pr state head squashed ahead
  fetch_base
  git rev-parse --verify -q "${BASE}^{commit}" >/dev/null ||
    die "${BASE} does not exist in this checkout, so '${br}' cannot be checked."

  if git merge-base --is-ancestor "${tip}" "${BASE}" 2>/dev/null; then
    ok "${br} has no commits of its own: everything on it is already on ${BASE}."
    exit 0
  fi

  base_tree="$(git rev-parse "${BASE}^{tree}")"
  if merged="$(git merge-tree --write-tree "${BASE}" "${tip}" 2>/dev/null | head -1)" &&
     [ "${merged}" = "${base_tree}" ]; then
    ok "${br} is landed: merging it into ${BASE} would change nothing (content check)."
    exit 0
  fi

  ahead="$(git rev-list --count "${BASE}..${tip}" 2>/dev/null || echo '?')"
  if command -v gh >/dev/null 2>&1; then
    pr_line="$(gh pr list --repo "${REPO}" --head "${br}" --state all \
      --json number,state,headRefOid,mergeCommit,createdAt \
      -q 'sort_by(.createdAt)|last|"\(.number) \(.state) \(.headRefOid) \(.mergeCommit.oid // "-")"' 2>/dev/null || true)"
    read -r pr state head squashed <<<"${pr_line}"
    if [ "${state:-}" = "MERGED" ] && [ -n "${squashed:-}" ] && [ "${squashed}" != "-" ] &&
       git merge-base --is-ancestor "${squashed}" "${BASE}" 2>/dev/null; then
      if [ "${tip}" = "${head}" ] ||
         { git cat-file -e "${head}^{commit}" 2>/dev/null &&
           git merge-base --is-ancestor "${tip}" "${head}" 2>/dev/null; }; then
        ok "${br} is landed: PR #${pr} merged as ${squashed:0:8}, and ${where} has nothing past the PR's head."
        exit 0
      fi
      if git cat-file -e "${head}^{commit}" 2>/dev/null && extras_on_base "${head}" "${tip}"; then
        ok "${br} is landed: PR #${pr} merged as ${squashed:0:8}, and what ${where} has past the PR's head is already on ${BASE} (empty, clean merges, or patches ${BASE} has)."
        exit 0
      fi
      die "${br} is NOT safe to delete: PR #${pr} merged, but ${where} has commits
   past what the PR merged (tip ${tip:0:8}, PR head ${head:0:8}) that are not on ${BASE}. Push or save them first."
    fi
    [ -n "${pr:-}" ] && [ "${pr}" != "null" ] &&
      die "${br} is NOT landed: ${ahead} commit(s) not on ${BASE}, and PR #${pr} is ${state:-unknown}."
  fi
  die "${br} is NOT landed: ${ahead} commit(s) not on ${BASE}, their changes are not on it
   either, and no merged pull request covers them."
}

if [ "${1:-}" = "--branch" ]; then
  [ -n "${2:-}" ] || die "usage: landed --branch <local-branch>"
  tip="$(git rev-parse --verify -q "refs/heads/${2}^{commit}")" || die "no local branch '${2}'."
  gate_branch "$2" "${tip}" "the local branch"
fi

if [ "${1:-}" = "--remote-branch" ]; then
  [ -n "${2:-}" ] || die "usage: landed --remote-branch <branch-on-origin>"
  # Fetched on its own, so the answer is about the branch as origin has it now,
  # not as this checkout last saw it.
  [ "${LANDED_NO_FETCH:-0}" = "1" ] ||
    git fetch -q origin "+refs/heads/${2}:refs/remotes/origin/${2}" 2>/dev/null ||
    die "could not fetch '${2}' from origin: no such branch there, or no network."
  tip="$(git rev-parse --verify -q "refs/remotes/origin/${2}^{commit}")" || die "no branch '${2}' on origin."
  gate_branch "$2" "${tip}" "the branch on origin"
fi

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

if [ -z "${state:-}" ]; then
  # Fallback: check if the commit already landed on BASE via squash title suffix "(#$pr)"
  fetch_base
  local_squashed="$(git log -1 --grep "(#${pr})" --format='%H' "${BASE}" 2>/dev/null || true)"
  if [ -n "${local_squashed}" ]; then
    ok "PR #${pr} is on ${BASE} as ${local_squashed:0:8} (squashed) [resolved via commit log]."
    info "$(git log -1 --format='%s' "${local_squashed}")"
    exit 0
  fi
  die "gh could not read PR #${pr} in ${REPO}."
fi

case "${state}" in
  MERGED) : ;;
  *) die "PR #${pr} is ${state}, not MERGED -- this work is NOT on ${BASE}.

   Do not push follow-up commits to a merged PR's branch either: the repo
   auto-deletes branches on merge, so a push silently re-creates a dangling one." ;;
esac

[ "${squashed}" != "-" ] ||
  die "PR #${pr} reports MERGED but exposes no merge commit, so it cannot be
   verified against ${BASE}. Check it by content instead."

fetch_base

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
