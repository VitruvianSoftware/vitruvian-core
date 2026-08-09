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

# Hermetic guard for tools/ci/bisect-culprit.sh. Builds a throwaway git repo
# per case (no network, no bazel — TEST_CMD is the script's own documented
# hook) and drives the script's input validation.
#
# THE CASE THIS FILE EXISTS FOR: GOOD_SHA == BAD_SHA. `--is-ancestor` cannot
# reject it, because a commit is its own ancestor — so the pre-existing
# ancestry guard exits 0 on the exact input its comment says degenerates
# bisect. Case 2 is the delete-the-fix control: it removes the equality guard
# and asserts the run reaches the MISLEADING diagnostic, so this file goes red
# if someone deletes the guard later. A guard with no test that fails toward
# silence is what the guard itself was added to stop.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/bisect-culprit.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }

# A repo with $1 commits; every commit writes its index to ./marker.
make_repo() {
  local dir="$1" n="$2" i
  mkdir -p "$dir" && git -C "$dir" init -q .
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  for ((i = 1; i <= n; i++)); do
    echo "$i" > "$dir/marker"
    git -C "$dir" add marker
    git -C "$dir" commit -qm "commit $i"
  done
}

echo "--- GOOD_SHA == BAD_SHA is rejected by the equality guard ---"
repo="$work/same"
make_repo "$repo" 3
S="$(git -C "$repo" rev-parse HEAD)"
out="$(cd "$repo" && env GOOD_SHA="$S" BAD_SHA="$S" TARGETS="//:noop" \
  TEST_CMD="true" bash "$SCRIPT" 2>&1)"
rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "are the same commit"; then
  pass "identical GOOD/BAD exits 2 naming the real cause"
else
  fail "identical GOOD/BAD — expected rc=2 and 'are the same commit', got rc=$rc: $out"
fi
# The contrast with the delete-the-fix case below: guarded, the script never
# reaches `git bisect start`, so git's own "was both 'good' and 'bad'" never
# appears and the exit code is 2 (input error) rather than 1 (bisect failed).
if printf '%s' "$out" | grep -q "was both 'good' and 'bad'"; then
  fail "identical GOOD/BAD still reached git bisect start — the guard is not short-circuiting"
else
  pass "git bisect start is never reached, so the failure is reported as an input error"
fi

echo "--- abbreviated vs full sha for the SAME commit is still rejected ---"
out="$(cd "$repo" && env GOOD_SHA="${S:0:8}" BAD_SHA="$S" TARGETS="//:noop" \
  TEST_CMD="true" bash "$SCRIPT" 2>&1)"
rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "are the same commit"; then
  pass "one commit spelled two ways is compared as a commit, not as a string"
else
  fail "abbreviated vs full — expected rc=2 and 'are the same commit', got rc=$rc: $out"
fi

echo "--- DELETE-THE-FIX control: without the guard, the diagnosis is wrong ---"
# Same input, against a copy of the script with the equality guard stripped.
# This is what the script did before this guard existed; if it ever stops
# reproducing, the guard has become unreachable rather than unnecessary.
python3 - "$SCRIPT" "$work/unguarded.sh" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
lines = open(src).read().splitlines(keepends=True)
# Find the `if` whose body carries the equality guard's error string, then drop
# through its matching `fi`. Located by the message rather than by line number,
# so this control survives edits above it.
hit = next(i for i, l in enumerate(lines) if "are the same commit" in l)
start = max(i for i in range(hit) if lines[i].startswith("if "))
end = next(i for i in range(hit, len(lines)) if lines[i].rstrip() == "fi")
open(dst, "w").write("".join(lines[:start] + lines[end + 1:]))
PY
bash -n "$work/unguarded.sh" || fail "control setup — stripped copy is not valid bash"
if grep -q "are the same commit" "$work/unguarded.sh"; then
  fail "control setup — the guard was not actually removed from the copy"
else
  out="$(cd "$repo" && env GOOD_SHA="$S" BAD_SHA="$S" TARGETS="//:noop" \
    TEST_CMD="true" bash "$work/unguarded.sh" 2>&1)"
  rc=$?
  # rc=1, not 2: `set -e` kills the script at `git bisect start`, so the input
  # error is reported under this script's "could not identify a culprit" code
  # rather than its "caller passed something wrong" code. That mislabelling is
  # the defect — NOT, as first characterised, reaching the "did not converge"
  # message, which measurement shows is never printed.
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "was both 'good' and 'bad'"; then
    pass "guard removed: dies at 'git bisect start' with rc=1 — an input error wearing the bisect-failed code"
  else
    fail "guard removed — expected rc=1 and \"was both 'good' and 'bad'\", got rc=$rc: $out"
  fi
  if printf '%s' "$out" | grep -q "did not converge"; then
    fail "guard removed — reached the converge message; the exit path has changed and this comment is stale"
  else
    pass "guard removed: the converge message is NOT reached (set -e stops it earlier)"
  fi
fi

echo "--- pre-existing ancestry guard still rejects unrelated histories ---"
repo2="$work/unrelated"
make_repo "$repo2" 2
# a commit on an orphan branch: not an ancestor of HEAD in either direction
git -C "$repo2" checkout -q --orphan other
echo other > "$repo2/marker"
git -C "$repo2" add marker
git -C "$repo2" commit -qm "orphan"
ORPHAN="$(git -C "$repo2" rev-parse HEAD)"
git -C "$repo2" checkout -q master 2>/dev/null || git -C "$repo2" checkout -q main
HEADC="$(git -C "$repo2" rev-parse HEAD)"
out="$(cd "$repo2" && env GOOD_SHA="$ORPHAN" BAD_SHA="$HEADC" TARGETS="//:noop" \
  TEST_CMD="true" bash "$SCRIPT" 2>&1)"
rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "not an ancestor"; then
  pass "non-ancestor GOOD still exits 2 with the ancestry message"
else
  fail "non-ancestor — expected rc=2 and 'not an ancestor', got rc=$rc: $out"
fi

echo "--- POSITIVE CONTROL: a real range still bisects (the guard does not over-fire) ---"
repo3="$work/real"
make_repo "$repo3" 5
GOOD="$(git -C "$repo3" rev-parse HEAD~4)"
BAD="$(git -C "$repo3" rev-parse HEAD)"
# "bad" from commit 3 onward: marker >= 3
# shellcheck disable=SC2016 # deliberate: TEST_CMD is evaluated by the script
# once per bisect step, so `$(cat marker)` must survive unexpanded to here.
out="$(cd "$repo3" && env GOOD_SHA="$GOOD" BAD_SHA="$BAD" TARGETS="//:noop" \
  GITHUB_OUTPUT="$work/gh_out" \
  TEST_CMD='test "$(cat marker)" -lt 3' bash "$SCRIPT" 2>&1)"
rc=$?
want="$(git -C "$repo3" rev-parse HEAD~2)"
got="$(sed -n 's/^culprit=//p' "$work/gh_out" 2>/dev/null)"
if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
  pass "real range converges on the expected culprit (${want:0:8})"
else
  fail "real range — expected rc=0 and culprit=${want:0:8}, got rc=$rc culprit=${got:0:8}: $out"
fi

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails" >&2; exit 1; fi
echo "ALL PASS"
