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

# release-main.sh — put the main checkout back on `main` when a session started
# with a branch checked out in it.
#
#   bazel run //tools/worktree:release-main
#
# Cloud sessions start with their assigned branch checked out in the main
# checkout. The main checkout must stay on main, commit refuses there, and
# `git worktree add` refuses to check the same branch out twice, so the branch
# can never get a worktree. This frees it: the main checkout moves to `main`
# (or, when `main` is not available, detaches at origin/main), then
# `bazel run //tools/worktree -- <branch>` makes the branch's worktree.
#
# Nothing is lost: the branch keeps its commits, and the main checkout must be
# clean (no edits, no untracked files) or this refuses.
set -euo pipefail

HERE="${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel)}"
cd "${HERE}"

# The main checkout is the first entry of `git worktree list`. Refuse to run
# from any other worktree: it would move the wrong tree.
MAIN="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
if [ "$(cd "${HERE}" && pwd -P)" != "$(cd "${MAIN}" && pwd -P)" ]; then
  echo "release-main: run this from the main checkout (${MAIN}), not from a worktree" >&2
  exit 1
fi

CURRENT="$(git symbolic-ref --quiet --short HEAD || true)"
if [ -z "${CURRENT}" ]; then
  echo "release-main: the main checkout is already detached; nothing to release"
  exit 0
fi
if [ "${CURRENT}" = "main" ]; then
  echo "release-main: the main checkout is already on main; nothing to release"
  exit 0
fi

if [ -n "$(git status --porcelain --untracked-files=all)" ]; then
  echo "release-main: the main checkout has uncommitted or untracked files; refusing." >&2
  echo "  Carry them to a worktree first: git diff HEAD --binary > wip.patch" >&2
  exit 1
fi

echo "release-main: main checkout is on ${CURRENT}; moving it off"

# Prefer the local main branch when no other worktree holds it.
if git show-ref --verify --quiet refs/heads/main \
  && ! git worktree list --porcelain | grep -qx 'branch refs/heads/main'; then
  git switch --quiet main
  echo "release-main: main checkout is now on main"
elif git show-ref --verify --quiet refs/remotes/origin/main; then
  git switch --quiet --detach origin/main
  echo "release-main: main checkout is now detached at origin/main"
else
  echo "release-main: neither main nor origin/main exists; nothing to move to" >&2
  exit 1
fi

cat <<DONE

  ${CURRENT} is free. Make its worktree:
    bazel run //tools/worktree -- ${CURRENT}
DONE
