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
LANDED="${2:?usage: worktree_test.sh <worktree.sh> <landed.sh>}"
LANDED="$(cd "$(dirname "$LANDED")" && pwd)/$(basename "$LANDED")"
export WORKTREE_LANDED="$LANDED"

# Resolved (macOS /var -> /private/var) so every path below matches what git
# records and what the tool hashes into an output-base name.
work="$(cd "$(mktemp -d)" && pwd -P)"
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
# A gh that cannot answer: the landed gate must stand on git alone, and the
# test must never reach the network.
mkdir -p "$work/bin"
printf '#!/usr/bin/env bash\nexit 1\n' >"$work/bin/gh"
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"
repo="$work/repo"
git init -q -b main "$repo"
cd "$repo" || exit 1
git config user.email t@t
git config user.name t
# As in the real repo, the user.bazelrc this tool writes is gitignored.
printf 'user.bazelrc\n' >.gitignore
git add .gitignore
git commit -q -m base
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

# 6. Uncommitted work is not deleted unless asked.
git worktree add -q -b fix/six "$work/wt/fix-six" main
echo "half-written" >"$work/wt/fix-six/notes.txt"
out="$(tool --remove fix/six 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && [ -f "$work/wt/fix-six/notes.txt" ] && grep -q "notes.txt" <<<"$out" && grep -q -- "--force" <<<"$out" && ! grep -q "worktree: removed" <<<"$out"; then
    pass "a worktree with uncommitted files is kept, and says how to remove it anyway"
else
    fail "uncommitted work was deleted without being asked (rc=$rc): $out"
fi
out="$(tool --remove fix/six --force 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$work/wt/fix-six" ] && grep -q "worktree: removed .*/wt/fix-six " <<<"$out"; then
    pass "--force removes it with its uncommitted files"
else
    fail "--force did not remove a worktree with uncommitted files (rc=$rc): $out"
fi

# 7. A locked worktree is somebody's work in progress: kept, even with --force.
git worktree add -q -b fix/seven "$work/wt/fix-seven" main
git worktree lock --reason "in use" "$work/wt/fix-seven"
out="$(tool --remove fix/seven --force 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && [ -d "$work/wt/fix-seven" ] && grep -q "locked" <<<"$out"; then
    pass "a locked worktree is kept"
else
    fail "a locked worktree was removed (rc=$rc): $out"
fi
git worktree unlock "$work/wt/fix-seven"

# 8. The branch is kept, as the tool says.
if git show-ref --verify --quiet refs/heads/fix/one && git show-ref --verify --quiet refs/heads/fix/two; then
    pass "keeps the branch"
else
    fail "removing a worktree deleted its branch"
fi

# ── helpers for the landed-gated cases ────────────────────────────────────────
# landed_branch <branch> <dir>: a worktree whose branch is SQUASH-merged: the
# branch has its own commit, and main carries the same change as a new commit.
landed_branch() {
    git worktree add -q -b "$1" "$2" main
    echo "$1" >"$2/$(printf '%s' "$1" | tr '/' '-').txt"
    git -C "$2" add -A
    git -C "$2" commit -qm "$1"
    git checkout -q main
    git checkout -q "$1" -- "$(printf '%s' "$1" | tr '/' '-').txt"
    git commit -qm "$1 (#1)"
    git update-ref refs/remotes/origin/main refs/heads/main
}
# unlanded_branch <branch> <dir>: a worktree with a commit main does not have.
unlanded_branch() {
    git worktree add -q -b "$1" "$2" main
    echo "wip" >"$2/wip-$(printf '%s' "$1" | tr '/' '-').txt"
    git -C "$2" add -A
    git -C "$2" commit -qm "wip $1"
}
# fake_server <pidfile>: a process that stands in for a Bazel server. Started in
# a subshell so it is re-parented and reaped by init when killed, rather than
# lingering as OUR zombie (which kill -0 would still report as alive).
fake_server() {
    mkdir -p "$(dirname "$1")"
    (sleep 300 >/dev/null 2>&1 & echo $! >"$1")
}
md5_of() {
  printf '%s' "$1" | { md5sum 2>/dev/null || /sbin/md5 -q 2>/dev/null || md5 -q 2>/dev/null || openssl md5 -r; } | cut -d' ' -f1
}
alive() { kill -0 "$(cat "$1")" 2>/dev/null; }
BAZEL_ROOT="$HOME/.cache/bazel/_bazel_${USER:-$(id -un)}"
git update-ref refs/remotes/origin/main refs/heads/main

# 9. Run from INSIDE a worktree: the repo is still the primary checkout.
git worktree add -q -b fix/inside "$work/wt/inside" main
git worktree add -q -b fix/nine "$work/wt/fix-nine" main
inside() { BUILD_WORKSPACE_DIRECTORY="$work/wt/inside" bash "$SCRIPT" "$@"; }
out="$(inside --remove fix/nine 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$work/wt/fix-nine" ] && [ -d "$work/wt/inside" ]; then
    pass "--remove from inside a worktree removes the named worktree, not the one it runs in"
else
    fail "--remove from inside a worktree misbehaved (rc=$rc): $out"
fi
out="$(inside --remove fix/inside 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && [ -d "$work/wt/inside" ] && grep -q "running from" <<<"$out" && ! grep -q "primary checkout, which" <<<"$out"; then
    pass "refuses to remove the worktree it is running from, and does not call it the primary"
else
    fail "removed (or misnamed) the worktree it runs from (rc=$rc): $out"
fi

# 10. Create from inside a worktree: lands beside the PRIMARY, with a marker.
out="$(inside fix/ten 2>&1)"
rc=$?
dest="$work/repo-worktrees/fix-ten"
marker="$HOME/.cache/bazel/worktrees/repo-fix-ten/.vitruvian-worktree"
if [ "$rc" -eq 0 ] && [ -d "$dest" ] && [ ! -e "$work/wt/inside-worktrees" ] && [ ! -e "$work/inside-worktrees" ]; then
    pass "create from inside a worktree puts it under <primary>-worktrees"
else
    fail "create from inside a worktree went to the wrong place (rc=$rc): $out"
fi
if [ -f "$marker" ] && [ "$(cat "$marker")" = "$dest" ]; then
    pass "writes the worktree path into its Bazel output root (for bazel-cache gc)"
else
    fail "no marker naming $dest in $marker: $(cat "$marker" 2>&1)"
fi

# 11. --remove --delete-branch on a clean, squash-landed branch: both go.
landed_branch fix/eleven "$work/wt/fix-eleven"
out="$(tool --remove fix/eleven --delete-branch 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$work/wt/fix-eleven" ] && ! git show-ref --verify --quiet refs/heads/fix/eleven; then
    pass "--delete-branch removes a clean, landed worktree and its branch"
else
    fail "--delete-branch did not remove a landed worktree + branch (rc=$rc): $out"
fi

# 12. ...but NOT an unlanded one: worktree and branch both kept.
unlanded_branch fix/twelve "$work/wt/fix-twelve"
out="$(tool --remove fix/twelve --delete-branch 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && [ -d "$work/wt/fix-twelve" ] && git show-ref --verify --quiet refs/heads/fix/twelve && grep -q "not landed" <<<"$out"; then
    pass "--delete-branch keeps an unlanded worktree and branch, and says why"
else
    fail "--delete-branch removed unlanded work (rc=$rc): $out"
fi

# 13. ...nor a dirty one, even a landed one, even with --force.
landed_branch fix/thirteen "$work/wt/fix-thirteen"
echo scratch >"$work/wt/fix-thirteen/scratch.txt"
out="$(tool --remove fix/thirteen --delete-branch --force 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && [ -f "$work/wt/fix-thirteen/scratch.txt" ] && git show-ref --verify --quiet refs/heads/fix/thirteen; then
    pass "--delete-branch keeps a dirty worktree even with --force"
else
    fail "--delete-branch removed a dirty worktree (rc=$rc): $out"
fi

# 14. Remove stops the Bazel server in BOTH output roots before deleting.
git worktree add -q -b fix/fourteen "$work/wt/fix-fourteen" main
root14="$HOME/.cache/bazel/worktrees/repo-fix-fourteen"
printf 'startup --output_user_root=%s\n' "$root14" >"$work/wt/fix-fourteen/user.bazelrc"
h="$(md5_of "$work/wt/fix-fourteen")"
fake_server "$BAZEL_ROOT/$h/server/server.pid.txt"
fake_server "$root14/$h/server/server.pid.txt"
p1="$(cat "$BAZEL_ROOT/$h/server/server.pid.txt")"
p2="$(cat "$root14/$h/server/server.pid.txt")"
out="$(tool --remove fix/fourteen 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] && ! kill -0 "$p1" 2>/dev/null && ! kill -0 "$p2" 2>/dev/null && [ ! -e "$root14" ]; then
    pass "stops the server in the default AND the per-worktree output root, then removes"
else
    fail "a Bazel server survived removal (rc=$rc, default alive=$(kill -0 "$p1" 2>/dev/null && echo y || echo n), own alive=$(kill -0 "$p2" 2>/dev/null && echo y || echo n)): $out"
fi
kill "$p1" "$p2" 2>/dev/null

# 15. --prune: one of each case. Only the clean, landed, unlocked one may go.
rm -rf "$work/wt/fix-thirteen/scratch.txt"
git worktree remove --force "$work/wt/fix-thirteen"
git branch -q -D fix/thirteen
landed_branch p/landed "$work/wt/p-landed"        # REMOVE
unlanded_branch p/unlanded "$work/wt/p-unlanded"  # KEEP: not landed
landed_branch p/dirty "$work/wt/p-dirty"          # KEEP: dirty
echo x >"$work/wt/p-dirty/untracked.txt"
landed_branch p/locked "$work/wt/p-locked"        # KEEP: locked
git worktree lock --reason "agent at work" "$work/wt/p-locked"
landed_branch p/busy "$work/wt/p-busy"            # KEEP: live Bazel server
fake_server "$BAZEL_ROOT/$(md5_of "$work/wt/p-busy")/server/server.pid.txt"
git worktree add -q -b p/new "$work/wt/p-new" main   # KEEP: no commits of its own
git worktree add -q --detach "$work/wt/p-detached" main # KEEP: detached
out="$(tool --prune 2>&1)"
rc=$?
kept_all=1
for d in p-landed p-unlanded p-dirty p-locked p-busy p-new p-detached; do [ -d "$work/wt/$d" ] || kept_all=0; done
if [ "$rc" -eq 0 ] && [ "$kept_all" = 1 ] && grep -q "DRY RUN" <<<"$out"; then
    pass "--prune is a dry run: removes nothing"
else
    fail "--prune without --execute changed something (rc=$rc): $out"
fi
want() { # <description> <path fragment> <KEEP|REMOVE> <reason fragment>
    if grep -A1 "^  $3 .*/wt/$2" <<<"$out" | grep -q "$4"; then pass "--prune: $1"; else fail "--prune: $1 -- expected $3 $2 ($4) in: $out"; fi
}
want "lists the clean landed worktree for removal" p-landed REMOVE "landed"
want "keeps an unlanded worktree" p-unlanded KEEP "not landed"
want "keeps a dirty worktree" p-dirty KEEP "uncommitted or untracked"
want "keeps a locked worktree, with its reason" p-locked KEEP "agent at work"
want "keeps a worktree with a live Bazel server" p-busy KEEP "in use"
want "keeps a branch with no commits of its own" p-new KEEP "no commits of its own"
want "keeps a detached worktree" p-detached KEEP "detached"
if grep -A1 "^  KEEP    $repo  (main)\$" <<<"$out" | grep -q "primary checkout"; then pass "--prune: keeps the primary checkout"; else fail "--prune: primary not reported kept: $out"; fi

out="$(tool --prune --execute 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$work/wt/p-landed" ] && ! git show-ref --verify --quiet refs/heads/p/landed; then
    pass "--prune --execute removes the clean landed worktree and its branch"
else
    fail "--prune --execute did not remove the landed worktree (rc=$rc): $out"
fi
survivors=1
for d in p-unlanded p-dirty p-locked p-busy p-new p-detached; do [ -d "$work/wt/$d" ] || survivors=0; done
for b in p/unlanded p/dirty p/locked p/busy p/new; do git show-ref --verify --quiet "refs/heads/$b" || survivors=0; done
if [ "$survivors" = 1 ] && [ -f "$work/wt/p-dirty/untracked.txt" ]; then
    pass "--prune --execute keeps every other worktree and branch"
else
    fail "--prune --execute removed something it must keep: $out"
fi
kill "$(cat "$BAZEL_ROOT/$(md5_of "$work/wt/p-busy")/server/server.pid.txt")" 2>/dev/null
git worktree unlock "$work/wt/p-locked"

echo "worktree_test: $pass_n passed, $fail_n failed"
[ "$fail_n" -eq 0 ]
