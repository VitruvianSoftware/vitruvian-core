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

# Hermetic guard for tools/ci/dependabot-lock-rebase.sh. Uses a REAL bare git
# "origin" plus a real clone as the script's working checkout (git merge and
# conflict resolution are the thing under test, same rationale as
# deploy-affected_test.sh's real-temp-git-repo pattern) and fakes `gh` (PR
# listing) and `bazel` (the pnpm/tidy reconcile) — no network, no real Bazel.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/dependabot-lock-rebase.sh"

fails=0
ok() { printf '  ok - %s\n' "$1"; }
bad() { printf '  NOT OK - %s\n' "$1" >&2; fails=$((fails + 1)); }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# --- fake gh: only `pr list` is used by this script -------------------------
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "pr list" ]; then
  printf '%s' "${FAKE_PR_LIST_OUT:-}"
  exit 0
fi
echo "unexpected fake gh invocation: $*" >&2
exit 99
EOF
chmod +x "$work/bin/gh"

# --- fake bazel: intercepts the two reconcile invocations -------------------
cat > "$work/bin/bazel" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "${FAKE_BAZEL_LOG}"
case "$*" in
  *"@pnpm//:pnpm"*)
    # app-4.txt exists only on pr4-branch's merge result — fail the pnpm
    # reconcile ONLY for that PR, so the other PRs' merges stay unaffected.
    [ -f app-4.txt ] && exit 1
    exit 0
    ;;
  *"//:tidy"*)
    exit 0
    ;;
  *)
    echo "unexpected fake bazel invocation: $*" >&2
    exit 99
    ;;
esac
EOF
chmod +x "$work/bin/bazel"

# --- build a real bare "origin" with main + several PR branches -------------
src="$work/src"
mkdir -p "$src"
git -C "$src" init -q -b main
git -C "$src" config user.email test@example.com
git -C "$src" config user.name test
printf 'v1\n' > "$src/app.txt"
printf 'lock-v1\n' > "$src/pnpm-lock.yaml"
git -C "$src" add -A
git -C "$src" commit -q -m "initial"

bare="$work/origin.git"
git clone -q --bare "$src" "$bare"

# branch <name> <from-ref-in-bare> — create+push a branch in the bare repo via
# a disposable scratch clone, running $3 (a shell snippet with $src cwd) to
# mutate files before committing.
mkscratch() {
  local scratch="$work/scratch-$1"
  git clone -q "$bare" "$scratch"
  git -C "$scratch" config user.email test@example.com
  git -C "$scratch" config user.name test
  printf '%s' "$scratch"
}

# PR 1: clean merge — touches only app-1.txt, no overlap with main's later move.
s="$(mkscratch pr1)"
git -C "$s" checkout -q -b pr1-branch
printf 'pr1\n' > "$s/app-1.txt"
git -C "$s" add -A && git -C "$s" commit -q -m "pr1 change"
git -C "$s" push -q origin pr1-branch

# PR 2: lock-only conflict — edits pnpm-lock.yaml; main will ALSO move it, so
# merging produces a conflict restricted to the lock file.
s="$(mkscratch pr2)"
git -C "$s" checkout -q -b pr2-branch
printf 'lock-v1-pr2\n' > "$s/pnpm-lock.yaml"
git -C "$s" add -A && git -C "$s" commit -q -m "pr2 dependabot bump"
git -C "$s" push -q origin pr2-branch

# PR 3: real conflict outside the lock file — edits app.txt; main will ALSO
# edit app.txt differently, so the conflict is NOT confined to the lock file
# and must be left for a human.
s="$(mkscratch pr3)"
git -C "$s" checkout -q -b pr3-branch
printf 'pr3-edit\n' > "$s/app.txt"
git -C "$s" add -A && git -C "$s" commit -q -m "pr3 change"
git -C "$s" push -q origin pr3-branch

# PR 4: clean merge, but the bazel reconcile fails — must leave the branch
# unpushed and report rc=1.
s="$(mkscratch pr4)"
git -C "$s" checkout -q -b pr4-branch
printf 'pr4\n' > "$s/app-4.txt"
git -C "$s" add -A && git -C "$s" commit -q -m "pr4 change"
git -C "$s" push -q origin pr4-branch

# advance main: moves both app.txt (conflicts with PR3) and pnpm-lock.yaml
# (conflicts with PR2, cleanly reconciles for PR1/PR4).
s="$(mkscratch mainadv)"
printf 'main-v2\n' > "$s/app.txt"
printf 'lock-v2\n' > "$s/pnpm-lock.yaml"
git -C "$s" add -A && git -C "$s" commit -q -m "main advances"
git -C "$s" push -q origin main

# Now create PR5 for real, branched from the ADVANCED main (so merging main
# into it is a true no-op).
s="$(mkscratch pr5)"
git -C "$s" push -q origin main:pr5-branch

# --- the script's own working checkout (mirrors actions/checkout) -----------
ws="$work/workdir"
git clone -q "$bare" "$ws"
git -C "$ws" config user.email placeholder@example.com
git -C "$ws" config user.name placeholder

prs_tsv="$(printf '1\tpr1-branch\n2\tpr2-branch\n3\tpr3-branch\n4\tpr4-branch\n5\tpr5-branch\n')"

run() {
  ( cd "$ws" && env PATH="$work/bin:$PATH" \
      FAKE_PR_LIST_OUT="$prs_tsv" FAKE_BAZEL_LOG="$work/bazel.log" \
      REPO="owner/repo" GH_TOKEN=x WORK_DIR="$work/scratch-out" \
      bash "$SCRIPT" )
}

: > "$work/bazel.log"
mkdir -p "$work/scratch-out"
set +e
out="$(run 2>&1)"
rc=$?
set -e

echo "$out" > "$work/full-output.log"

echo "--- overall exit status ---"
if [ "$rc" -eq 1 ]; then
  ok "overall exit is 1 (PR3's real conflict and PR4's reconcile failure both set rc=1)"
else
  bad "expected overall exit 1, got $rc"; sed 's/^/    /' "$work/full-output.log" >&2
fi

echo "--- PR1: clean merge, no lock conflict, pushed ---"
head="$(git -C "$bare" rev-parse pr1-branch)"
if git -C "$bare" merge-base --is-ancestor "$(git -C "$bare" rev-parse main)" "$head" 2>/dev/null \
   && echo "$out" | grep -q '#1: rebased onto main and pushed.'; then
  ok "pr1-branch was fast-forwarded past main and pushed"
else
  bad "pr1-branch not correctly rebased/pushed"
fi

echo "--- PR2: lock-only conflict auto-resolved, pushed ---"
head="$(git -C "$bare" rev-parse pr2-branch)"
if git -C "$bare" merge-base --is-ancestor "$(git -C "$bare" rev-parse main)" "$head" 2>/dev/null \
   && echo "$out" | grep -q '#2: rebased onto main and pushed.'; then
  ok "pr2-branch's lock-only conflict was auto-resolved and pushed"
else
  bad "pr2-branch not correctly resolved/pushed"
fi

echo "--- PR3: non-lock conflict left for a human, NOT pushed ---"
head="$(git -C "$bare" rev-parse pr3-branch)"
if echo "$out" | grep -q '::warning::#3: conflicts outside pnpm-lock.yaml, leaving for a human:' \
   && echo "$out" | grep -qE '^\s*app\.txt$'; then
  ok "pr3-branch's real conflict was correctly detected and warned about"
else
  bad "pr3-branch conflict handling wrong"
fi
if ! git -C "$bare" merge-base --is-ancestor "$(git -C "$bare" rev-parse main)" "$head" 2>/dev/null; then
  ok "pr3-branch was left unpushed (main not merged into it on the remote)"
else
  bad "pr3-branch should NOT have been pushed"
fi

echo "--- PR4: bazel reconcile failure, NOT pushed ---"
if echo "$out" | grep -q '::error::#4: pnpm re-resolve failed; leaving the branch untouched.'; then
  ok "pr4's simulated pnpm failure is reported"
else
  bad "pr4 reconcile-failure message missing"
fi
head="$(git -C "$bare" rev-parse pr4-branch)"
if ! git -C "$bare" merge-base --is-ancestor "$(git -C "$bare" rev-parse main)" "$head" 2>/dev/null; then
  ok "pr4-branch was left unpushed after the reconcile failure"
else
  bad "pr4-branch should NOT have been pushed after a reconcile failure"
fi

echo "--- PR5: already current with main, no push attempted ---"
if echo "$out" | grep -q '#5: already current with main — nothing to push.'; then
  ok "pr5-branch (already containing main's tip) reports nothing-to-push"
else
  bad "pr5-branch already-current path wrong"
fi

echo "--- bazel invocations happened for every PR whose merge succeeded (1, 2, 4, 5) ---"
pnpm_calls="$(grep -c '@pnpm//:pnpm' "$work/bazel.log" || true)"
if [ "$pnpm_calls" -eq 4 ]; then
  ok "pnpm reconcile ran exactly 4 times (PR3's aborted merge is the only one skipped)"
else
  bad "expected exactly 4 pnpm reconcile calls, got $pnpm_calls"
fi

if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails" >&2
  echo "--- full script output ---" >&2
  sed 's/^/    /' "$work/full-output.log" >&2
  exit 1
fi
echo "ALL PASS"
