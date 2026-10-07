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

# Hermetic guard for tools/ci/rdeps-map-ref.sh (#2841): a real bare repository
# stands in for GitHub, so save / fetch / prune run the same git commands they
# run in CI. No network, no token.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/rdeps-map-ref.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git init -q --bare "$work/remote.git"
git init -q -b main "$work/repo"
repo="$work/repo"
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
git -C "$repo" remote add origin "$work/remote.git"
shas=()
for i in 1 2 3 4 5 6; do
  echo "$i" > "$repo/f"
  git -C "$repo" add f && git -C "$repo" commit -q -m "c$i"
  shas+=("$(git -C "$repo" rev-parse HEAD)")
done
git -C "$repo" push -q origin main

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }
run() { (cd "$repo" && env -u GH_TOKEN -u GITHUB_OUTPUT "$@" bash "$SCRIPT" "${args[@]}" 2>"$work/err"); }
mkmap() { printf '{"schema":1,"commit":"%s","packages":["a"]}' "$1" > "$work/map.json"; }
remote_has() { git -C "$work/remote.git" show-ref --verify --quiet "refs/rdeps-map/$1"; }

echo "save"
mkmap "${shas[1]}"; args=(save "$work/map.json" "${shas[1]}"); run
remote_has "${shas[1]}" && pass "map stored at refs/rdeps-map/<sha>" || fail "ref missing: $(cat "$work/err")"
args=(save "$work/map.json" "${shas[2]}"); run
{ [ $? -ne 0 ] && ! remote_has "${shas[2]}"; } && pass "refuses a map that describes a different commit" || fail "saved a mislabelled map"
args=(save "$work/map.json" "not-a-sha"); run
[ $? -eq 2 ] && pass "refuses a ref name that is not a full sha" || fail "accepted a bad sha"
[ -z "$(git -C "$work/remote.git" for-each-ref refs/heads refs/tags | grep -v 'refs/heads/main')" ] \
  && pass "no branch or tag was created" || fail "created a branch or tag"

echo "fetch"
args=(fetch "$work/out.json" "${shas[1]}"); out="$(run)"
{ [ "$out" = "commit=${shas[1]}" ] && cmp -s "$work/map.json" "$work/out.json"; } \
  && pass "exact base: map returned byte for byte" || fail "got '$out': $(cat "$work/err")"
rm -f "$work/out.json"; args=(fetch "$work/out.json" "${shas[3]}"); out="$(run)"
{ [ "$out" = "commit=${shas[1]}" ] && grep -q '2 commit(s) behind' "$work/err"; } \
  && pass "base without a map: nearest ancestor's map returned" || fail "got '$out': $(cat "$work/err")"
mkmap "${shas[2]}"; args=(save "$work/map.json" "${shas[2]}"); run
args=(fetch "$work/out.json" "${shas[3]}"); out="$(run)"
[ "$out" = "commit=${shas[2]}" ] && pass "prefers the nearer of two ancestors" || fail "got '$out'"
rm -f "$work/out.json"; args=(fetch "$work/out.json" "${shas[5]}"); out="$(run RDEPS_MAP_MAX_BEHIND=1)"
{ [ "$out" = "commit=" ] && [ ! -e "$work/out.json" ]; } && pass "nothing within the limit: no file, empty result, exit 0" || fail "got '$out'"
args=(fetch "$work/out.json" "${shas[0]}"); out="$(run)"
[ "$out" = "commit=" ] && pass "a map for a LATER commit is never returned" || fail "got '$out'"
args=(fetch "$work/out.json" "0000000000000000000000000000000000000000"); out="$(run)"
[ "$out" = "commit=" ] && pass "unresolvable base: empty result, exit 0" || fail "got '$out'"
bad="$(printf '{"commit":"%s"}' "${shas[0]}" | git -C "$repo" hash-object -w --stdin)"
git -C "$repo" push -q origin "+${bad}:refs/rdeps-map/${shas[4]}"
args=(fetch "$work/out.json" "${shas[4]}"); out="$(run)"
[ "$out" = "commit=${shas[2]}" ] && pass "a mislabelled map on the remote is skipped, the next ancestor used" || fail "got '$out'"
: > "$work/gho"; args=(fetch "$work/out.json" "${shas[2]}"); (cd "$repo" && env -u GH_TOKEN GITHUB_OUTPUT="$work/gho" bash "$SCRIPT" "${args[@]}" >/dev/null 2>&1)
grep -qx "commit=${shas[2]}" "$work/gho" && pass "writes commit= to GITHUB_OUTPUT" || fail "GITHUB_OUTPUT: $(cat "$work/gho")"

echo "prune"
args=(prune); run RDEPS_MAP_KEEP=4   # keeps commits 3..6 (indexes 2..5)
{ ! remote_has "${shas[1]}" && remote_has "${shas[2]}" && remote_has "${shas[4]}"; } \
  && pass "drops maps older than the last KEEP commits, keeps the rest" || fail "after prune: $(git -C "$work/remote.git" for-each-ref refs/rdeps-map) $(cat "$work/err")"
args=(prune); run RDEPS_MAP_KEEP=1
{ remote_has "${shas[2]}" && grep -q 'pruning nothing' "$work/err"; } \
  && pass "with too little history to judge, prunes nothing" || fail "pruned on thin history: $(cat "$work/err")"
git -C "$work/remote.git" show-ref --verify --quiet refs/heads/main && pass "main untouched" || fail "main is gone"

echo
if [ "$fails" -gt 0 ]; then echo "$fails check(s) FAILED" >&2; exit 1; fi
echo "all rdeps-map-ref checks passed"
