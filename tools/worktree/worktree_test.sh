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

# worktree_test.sh — `--remove` must remove the worktree a branch is checked
# out in, wherever that is, and must not say "removed" when it removed nothing.
#
# It used to build the path from the branch name and ignore every error, so a
# worktree made by hand under another directory name was left on disk while the
# tool printed "removed" and exited 0.
set -uo pipefail

SCRIPT="${1:?usage: worktree_test.sh <path to worktree.sh>}"
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass_n=0
fail_n=0
pass() {
    echo "  ✓ $1"
    pass_n=$((pass_n + 1))
}
fail() {
    echo "  ✗ $1" >&2
    fail_n=$((fail_n + 1))
}

# A throwaway repo and HOME: the tool prunes a Bazel cache under $HOME, and
# must never see the real one. BUILD_WORKSPACE_DIRECTORY points it at the repo,
# as `bazel run` would.
export HOME="$work/home"
mkdir -p "$HOME"
repo="$work/repo"
git init -q -b main "$repo"
cd "$repo" || exit 1
git config user.email t@t
git config user.name t
git commit -q --allow-empty -m base
tool() { BUILD_WORKSPACE_DIRECTORY="$repo" WORKTREE_ROOT="$work/wt" bash "$SCRIPT" "$@"; }

# 1. A worktree at the path the tool itself would choose.
git worktree add -q -b fix/one "$work/wt/fix-one" main
out="$(tool --remove fix/one 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$work/wt/fix-one" ] && grep -q "worktree: removed .*/wt/fix-one " <<<"$out"; then
    pass "removes a worktree at the path it would have made"
else
    fail "a worktree at the tool's own path was not removed (rc=$rc): $out"
fi

# 2. A worktree made by hand under another name: found by its branch.
git worktree add -q -b fix/two "$work/wt/some-other-name" main
out="$(tool --remove fix/two 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$work/wt/some-other-name" ] && grep -q "worktree: removed .*/wt/some-other-name " <<<"$out"; then
    pass "removes the worktree a branch is checked out in, whatever its directory is called"
else
    fail "a worktree under another name was left behind (rc=$rc): $out"
fi

# 3. A branch with no worktree: say so, and fail.
git branch -q fix/three main
out="$(tool --remove fix/three 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && ! grep -q "worktree: removed" <<<"$out" && grep -q "no worktree" <<<"$out"; then
    pass "a branch with no worktree is an error, not a removal"
else
    fail "claimed to remove a worktree that does not exist (rc=$rc): $out"
fi

# 4. The Bazel cache named after the branch goes with the worktree.
git worktree add -q -b fix/four "$work/wt/fix-four" main
cache="$HOME/.cache/bazel/worktrees/repo-fix-four"
mkdir -p "$cache/x"
out="$(tool --remove fix/four 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$cache" ] && [ ! -e "$work/wt/fix-four" ]; then
    pass "prunes the worktree's Bazel cache"
else
    fail "the Bazel cache was left behind (rc=$rc): $out"
fi

# 5. The primary checkout is never removed, even when asked by its branch.
out="$(tool --remove main 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && [ -d "$repo/.git" ] && ! grep -q "worktree: removed" <<<"$out"; then
    pass "refuses to remove the primary checkout"
else
    fail "tried to remove the primary checkout (rc=$rc): $out"
fi

# 6. The branch is kept, as the tool says.
if git show-ref --verify --quiet refs/heads/fix/one && git show-ref --verify --quiet refs/heads/fix/two; then
    pass "keeps the branch"
else
    fail "removing a worktree deleted its branch"
fi

echo "worktree_test: $pass_n passed, $fail_n failed"
[ "$fail_n" -eq 0 ]
