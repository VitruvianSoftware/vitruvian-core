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

# dependabot-lock-rebase.sh — rebase every open Dependabot npm PR onto the
# just-merged root lock file, re-resolving it hermetically rather than asking
# Dependabot to (see dependabot-lock-rebase.yml's header for why: Dependabot
# only honours @dependabot commands from a real collaborator, never an App).
#
# For each open PR whose branch starts with BRANCH_PREFIX:
#   1. merge BASE_BRANCH into it (a merge, not a rebase — one extra commit is
#      far gentler on Dependabot than a force-pushed rewritten history);
#   2. if that merge conflicts, the ONLY conflict this script is competent to
#      resolve is LOCK_FILE itself — regenerating rather than picking a side,
#      since neither side is right once both manifests moved. Any other
#      conflicting path is a real semantic conflict and is left for a human;
#   3. re-resolve the lock with the same hermetic `@pnpm//:pnpm install
#      --lockfile-only` + `//:tidy` reconcile that runs at PR-creation time;
#   4. push, if the branch actually moved.
#
# Environment:
#   REPO             owner/repo (required)
#   GH_TOKEN         token gh uses; also what the eventual `git push` authenticates as
#   BASE_BRANCH      branch to merge in (default: main)
#   LOCK_FILE        the shared lock file (default: pnpm-lock.yaml)
#   BRANCH_PREFIX    only PR branches starting with this are touched
#                    (default: dependabot/npm_and_yarn/)
#   GIT_USER_NAME    commit identity for the merge/reconcile commits
#                    (default: VitruvianSoftware Sync)
#   GIT_USER_EMAIL   (default: sync@vitruviansoftware.com)
#   WORK_DIR         scratch dir for the PR list file; defaults to
#                    $RUNNER_TEMP (set on every GitHub Actions runner) and
#                    falls back to a fresh mktemp -d for local/test runs.
#
# Exit: 0 if every PR was rebased (or already current) cleanly; 1 if ANY PR
# hit a real conflict, a re-resolve failure, or a push failure (the others are
# still attempted — one bad PR must not block the rest).

set -uo pipefail

REPO="${REPO:?REPO must be set (owner/repo)}"
BASE_BRANCH="${BASE_BRANCH:-main}"
LOCK_FILE="${LOCK_FILE:-pnpm-lock.yaml}"
BRANCH_PREFIX="${BRANCH_PREFIX:-dependabot/npm_and_yarn/}"
GIT_USER_NAME="${GIT_USER_NAME:-VitruvianSoftware Sync}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-sync@vitruviansoftware.com}"
WORK_DIR="${WORK_DIR:-${RUNNER_TEMP:-$(mktemp -d)}}"

# gh's --jq takes a plain filter string with no --arg equivalent (see
# notify-ci-issues.yaml's header for the same limitation), so BRANCH_PREFIX is
# shell-interpolated here exactly as it was hardcoded before extraction. It is
# workflow-supplied config, never attacker-controlled PR content.
filter=".[] | select(.headRefName | startswith(\"${BRANCH_PREFIX}\")) | [.number,.headRefName] | @tsv"
prs="$(gh pr list -R "$REPO" --state open --json number,headRefName --jq "$filter")"
if [ -z "${prs}" ]; then
  echo "No open Dependabot npm PRs — nothing to rebase."
  exit 0
fi

git config user.name "${GIT_USER_NAME}"
git config user.email "${GIT_USER_EMAIL}"

# Redirected from a FILE, deliberately. Piping into `while` runs the loop body
# in a SUBSHELL, so every `rc=1` below would be discarded and the final
# `exit "${rc}"` would report success no matter what failed — the same
# silently-green failure this rewrite exists to remove.
printf '%s\n' "${prs}" > "${WORK_DIR}/prs.tsv"

rc=0
while IFS="$(printf '\t')" read -r num branch; do
  [ -n "${num}" ] || continue
  echo "::group::#${num} (${branch})"

  if ! git fetch --quiet origin "${branch}"; then
    echo "::warning::#${num}: cannot fetch ${branch}; skipping."
    echo "::endgroup::"; continue
  fi
  git checkout --quiet --force -B "rebase-${num}" "origin/${branch}"

  # Merge, not rebase: a merge touches the branch once, and Dependabot treats
  # a single extra commit far more gracefully than the rewritten history a
  # force-push would leave.
  if ! git merge --no-edit "origin/${BASE_BRANCH}"; then
    # The ONLY conflict this script is competent to resolve is the lock file,
    # and it does so by regenerating rather than by picking a side — neither
    # side is right once both manifests moved. Anything else is a real
    # semantic conflict and belongs to a human.
    unmerged="$(git diff --name-only --diff-filter=U)"
    if [ "${unmerged}" != "${LOCK_FILE}" ]; then
      echo "::warning::#${num}: conflicts outside ${LOCK_FILE}, leaving for a human:"
      printf '%s\n' "${unmerged}" | sed 's/^/    /'
      git merge --abort || true
      rc=1
      echo "::endgroup::"; continue
    fi
    git checkout --theirs -- "${LOCK_FILE}" || git checkout "origin/${BASE_BRANCH}" -- "${LOCK_FILE}"
    git add -- "${LOCK_FILE}"
    git commit --no-edit --quiet
  fi

  # Re-resolve from the MERGED manifests with the same hermetic pnpm
  # tidy-check asserts against, then converge generated/formatted output
  # exactly as dependabot-bazel-reconcile.yml does. That workflow will NOT
  # re-run for this push (its `if` excludes bot actors other than
  # Dependabot), so the reconcile has to happen here. Checked, not assumed:
  # without `-e` a failing reconcile would otherwise push a half-resolved
  # lock, which is strictly worse than leaving the PR stale.
  if ! bazel run -- @pnpm//:pnpm install --dir "$PWD" --lockfile-only; then
    echo "::error::#${num}: pnpm re-resolve failed; leaving the branch untouched."
    rc=1; echo "::endgroup::"; continue
  fi
  if ! bazel run //:tidy; then
    echo "::error::#${num}: //:tidy failed; leaving the branch untouched."
    rc=1; echo "::endgroup::"; continue
  fi

  git add -A
  if ! git diff --cached --quiet; then
    git commit --quiet -m "chore(deps): reconcile lock against ${BASE_BRANCH} (automated)"
  fi

  # Compare COMMITS, not trees. `git merge` with nothing to do leaves HEAD
  # exactly at origin/<branch>, which is the real "nothing to push" case. A
  # tree comparison would instead swallow a legitimate merge commit whose
  # tree happens to match, leaving the PR looking rebased locally while
  # BASE_BRANCH never actually got merged into it.
  if [ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/${branch}")" ]; then
    echo "#${num}: already current with ${BASE_BRANCH} — nothing to push."
  elif git push --quiet origin "HEAD:${branch}"; then
    echo "#${num}: rebased onto ${BASE_BRANCH} and pushed."
  else
    echo "::error::#${num}: push failed."
    rc=1
  fi
  echo "::endgroup::"
done < "${WORK_DIR}/prs.tsv"

exit "${rc}"
