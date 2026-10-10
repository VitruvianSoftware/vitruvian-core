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

# worktree.sh — create an isolated git worktree that also gets its OWN Bazel
# server, so multiple concurrent sessions/agents don't stomp a shared HEAD or
# contend on one output_base (issue #455).
#
# This checkout is routinely shared across sessions; branch work MUST happen in
# a worktree. This wraps `git worktree add` and, crucially, writes a per-worktree
# gitignored `user.bazelrc` pinning a unique `--output_user_root` so each
# worktree runs its own Bazel server + analysis cache.
#
# Usage (run through Bazel so $BUILD_WORKSPACE_DIRECTORY points at the checkout):
#   bazel run //tools/worktree -- <branch> [base-ref]   # create (base defaults to origin/main)
#   bazel run //tools/worktree -- --list                # list worktrees
#   bazel run //tools/worktree -- --remove <branch>     # remove the worktree for <branch>
#   bazel run //tools/worktree -- --remove <branch> --force   # ...with its uncommitted files
#
# Environment:
#   WORKTREE_ROOT  parent dir for worktrees (default: <repo-parent>/<repo>-worktrees)

set -euo pipefail

usage() {
  sed -n '22,38p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Resolve the repo root: prefer BUILD_WORKSPACE_DIRECTORY (set by `bazel run`),
# fall back to git so the script also works when invoked directly.
REPO="${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
if [ -z "${REPO}" ]; then
  echo "worktree: not inside a git repo and BUILD_WORKSPACE_DIRECTORY is unset" >&2
  exit 1
fi
cd "${REPO}"

REPO_NAME="$(basename "${REPO}")"
WT_ROOT="${WORKTREE_ROOT:-$(dirname "${REPO}")/${REPO_NAME}-worktrees}"

# slugify a branch name into a filesystem-safe directory component.
slug() { printf '%s' "$1" | tr '/' '-'; }

case "${1:-}" in
  ""|-h|--help)
    usage
    exit 0
    ;;
  --list)
    git worktree list
    exit 0
    ;;
  --remove)
    br="${2:?--remove needs a <branch>}"
    force=0
    if [ "${3:-}" = "--force" ]; then force=1; fi
    # Where the branch is checked out, as git records it. A worktree made by
    # hand, or under another WORKTREE_ROOT, is not at the path this tool would
    # have chosen, so the path is looked up, not built from the name.
    dest="$(git worktree list --porcelain | awk -v ref="refs/heads/${br}" '
      /^worktree /{path = substr($0, 10)}
      $1 == "branch" && $2 == ref {print path; exit}')"
    if [ -z "${dest}" ]; then
      echo "worktree: no worktree has branch ${br} checked out (see --list)" >&2
      exit 1
    fi
    if [ "$(cd "${dest}" 2>/dev/null && pwd -P)" = "$(pwd -P)" ]; then
      echo "worktree: ${br} is checked out in the primary checkout, which is not removed" >&2
      exit 1
    fi
    # A locked worktree is somebody's work in progress. It is kept, with or
    # without --force: unlock it first (git worktree unlock <path>).
    if git worktree list --porcelain | awk -v path="${dest}" '
        /^worktree /{here = (substr($0, 10) == path)}
        here && /^locked/{found = 1}
        END{exit !found}'; then
      echo "worktree: ${dest} is locked, so it is kept. Unlock it first: git worktree unlock ${dest}" >&2
      exit 1
    fi
    # Uncommitted or untracked files are work nobody has saved. They are kept
    # unless --force says otherwise. (Ignored files, such as the user.bazelrc
    # this tool writes, do not count.)
    unsaved="$(git -C "${dest}" status --porcelain 2>/dev/null || true)"
    if [ -n "${unsaved}" ] && [ "${force}" != "1" ]; then
      {
        echo "worktree: ${dest} has uncommitted or untracked files, so it is kept:"
        printf '%s\n' "${unsaved}" | head -20 | sed 's/^/  /'
        echo "worktree: commit them, or remove it anyway with: --remove ${br} --force"
      } >&2
      exit 1
    fi
    output_root="${HOME}/.cache/bazel/worktrees/${REPO_NAME}-$(slug "${br}")"
    if [ -d "${dest}" ] && [ -f "${dest}/user.bazelrc" ]; then
      (cd "${dest}" && bazel shutdown 2>/dev/null || true)
    fi
    if [ -n "${unsaved}" ]; then
      if ! git worktree remove --force "${dest}"; then
        echo "worktree: could not remove ${dest}" >&2
        exit 1
      fi
      echo "worktree: ${dest} had uncommitted or untracked files; they were removed with it" >&2
    elif ! git worktree remove "${dest}"; then
      echo "worktree: could not remove ${dest}" >&2
      exit 1
    fi
    git worktree prune 2>/dev/null || true
    if [ -e "${dest}" ]; then
      echo "worktree: ${dest} is still on disk after removal" >&2
      exit 1
    fi
    if [ -d "${output_root}" ]; then
      chmod -R u+w "${output_root}" 2>/dev/null || true
      rm -rf "${output_root}"
      echo "worktree: pruned Bazel cache ${output_root}"
    fi
    echo "worktree: removed ${dest} (branch ${br} is kept; delete with 'git branch -D ${br}')"
    exit 0
    ;;
esac

BRANCH="$1"
BASE="${2:-}"
DEST="${WT_ROOT}/$(slug "${BRANCH}")"

if [ -e "${DEST}" ]; then
  echo "worktree: destination already exists: ${DEST}" >&2
  exit 1
fi

# Default base: origin/main if present, else the current HEAD.
if [ -z "${BASE}" ]; then
  if git show-ref --verify --quiet refs/remotes/origin/main; then
    BASE="origin/main"
  else
    BASE="HEAD"
  fi
fi

mkdir -p "${WT_ROOT}"

# Create the worktree. Reuse an existing branch if it already exists; otherwise
# create it at BASE.
if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  git worktree add "${DEST}" "${BRANCH}"
else
  git worktree add -b "${BRANCH}" "${DEST}" "${BASE}"
fi

# Per-worktree Bazel server. Written to the gitignored user.bazelrc that
# .bazelrc try-imports (`try-import %workspace%/user.bazelrc`), so it applies
# ONLY to this worktree and is never committed.
OUTPUT_ROOT="${HOME}/.cache/bazel/worktrees/${REPO_NAME}-$(slug "${BRANCH}")"
cat > "${DEST}/user.bazelrc" <<EOF
# Auto-generated by //tools/worktree (issue #455). Gives this worktree its own
# Bazel server + analysis cache so it doesn't contend with the main checkout or
# sibling worktrees. Safe to edit or delete. Not committed (user.bazelrc is
# gitignored).
startup --output_user_root=${OUTPUT_ROOT}
EOF

# Propagate the PRIMARY checkout's build-cache setup (#506): the shared-cache
# default + auth headers live in the primary user.bazelrc (written by
# //tools/remote:setup), which git worktrees do NOT inherit — without this
# copy every worktree silently cold-builds with no remote cache. Copies the
# managed block plus the config=remote-scoped header lines; both are inert if
# the primary has no cache configured.
if [ -f "${REPO}/user.bazelrc" ]; then
  {
    awk '/^# >>> build cache \(managed by tools\/remote:setup\)/{inblk=1}
         inblk{print}
         /^# <<< build cache \(managed by tools\/remote:setup\)/{inblk=0}' "${REPO}/user.bazelrc"
    grep -E '^common:remote --(remote_header|bes_header)=' "${REPO}/user.bazelrc" || true
  } >> "${DEST}/user.bazelrc"
fi

cat <<EOF

  ✔ worktree ready
    branch:             ${BRANCH}
    path:               ${DEST}
    base:               ${BASE}
    bazel output root:  ${OUTPUT_ROOT}
                        (pinned in ${DEST}/user.bazelrc)

  next:
    cd ${DEST}
EOF
