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

# release-main_test.sh — release-main.sh moves the main checkout off a branch,
# and refuses on a dirty tree or from a linked worktree.
set -uo pipefail
SCRIPT="$(cd "$(dirname "${1:?usage: release-main_test.sh <release-main.sh>}")" && pwd -P)/$(basename "$1")"
FAILS=0
fail() { echo "FAIL: $*" >&2; FAILS=$((FAILS + 1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "${ROOT}"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset BUILD_WORKSPACE_DIRECTORY

new_repo() {
  rm -rf "${ROOT}/r" "${ROOT}/wt"
  git init -q -b main "${ROOT}/r"
  git -C "${ROOT}/r" commit -q --allow-empty -m base
  git -C "${ROOT}/r" branch feat
  git -C "${ROOT}/r" switch -q feat
}

# 1. clean tree on a branch: main checkout goes back to main
new_repo
out="$(cd "${ROOT}/r" && "${SCRIPT}" 2>&1)" || fail "clean run failed: ${out}"
[ "$(git -C "${ROOT}/r" branch --show-current)" = "main" ] || fail "not on main after release"
git -C "${ROOT}/r" worktree add -q "${ROOT}/wt" feat || fail "feat still not free for a worktree"

# 2. already on main: no-op
out="$(cd "${ROOT}/r" && "${SCRIPT}" 2>&1)" || fail "no-op run failed"
case "${out}" in *"nothing to release"*) ;; *) fail "expected no-op message, got: ${out}" ;; esac

# 3. dirty tree: refuses and stays on the branch
new_repo
touch "${ROOT}/r/stray"
if (cd "${ROOT}/r" && "${SCRIPT}" >/dev/null 2>&1); then fail "dirty tree was not refused"; fi
[ "$(git -C "${ROOT}/r" branch --show-current)" = "feat" ] || fail "dirty refusal moved the checkout"

# 4. main held by another worktree: detaches at origin/main instead
new_repo
git -C "${ROOT}/r" remote add origin "${ROOT}/r"
git -C "${ROOT}/r" fetch -q origin
git -C "${ROOT}/r" worktree add -q "${ROOT}/wt" main
(cd "${ROOT}/r" && "${SCRIPT}" >/dev/null 2>&1) || fail "detach fallback failed"
[ -z "$(git -C "${ROOT}/r" branch --show-current)" ] || fail "expected detached HEAD"

# 5. from a linked worktree: refuses
if (cd "${ROOT}/wt" && "${SCRIPT}" >/dev/null 2>&1); then fail "linked worktree was not refused"; fi

[ "${FAILS}" -eq 0 ] && echo "PASS" || exit 1
