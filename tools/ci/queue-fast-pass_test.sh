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

# Guard for tools/ci/queue-fast-pass.sh (#2841). A real git repository supplies
# the tree hash and a stub `gh` on PATH plays GitHub, answering from JSON files
# the test writes. The point of most cases is that doubt is always a miss.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/queue-fast-pass.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

repo="$work/repo"
git init -q -b main "$repo"
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
echo one >"$repo/f"
git -C "$repo" add f && git -C "$repo" commit -q -m c1
tree="$(git -C "$repo" rev-parse 'HEAD^{tree}')"
marker="passed-presubmit-${tree}"

# Stub gh: `gh api <path>` prints $work/api/<path with / ? & = turned into _>,
# or fails when that file is absent.
mkdir -p "$work/bin" "$work/api"
cat >"$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
[ "$1" = api ] || exit 64
echo "$2" >>"$GH_STUB_DIR/calls"
f="$GH_STUB_DIR/$(printf '%s' "$2" | tr '/?&=' '____')"
[ -f "$f" ] || exit 1
cat "$f"
STUB
chmod +x "$work/bin/gh"
key() { printf '%s' "$1" | tr '/?&=' '____'; }
list_path="repos/o/r/actions/artifacts?name=${marker}&per_page=30"
artifacts() { printf '%s' "$1" >"$work/api/$(key "$list_path")"; }
run_json() { printf '%s' "$2" >"$work/api/$(key "repos/o/r/actions/runs/$1")"; }
artifact() { # id run_id head_repo_id expired
	printf '{"name":"%s","expired":%s,"created_at":"2026-10-09T0%s:00:00Z","workflow_run":{"id":%s,"repository_id":7,"head_repository_id":%s}}' \
		"$marker" "${4:-false}" "$1" "$2" "${3:-7}"
}
good_run() { # id [event] [conclusion] [repo] [path]
	printf '{"id":%s,"event":"%s","conclusion":"%s","head_repository":{"full_name":"%s"},"path":"%s"}' \
		"$1" "${2:-pull_request}" "${3:-success}" "${4:-o/r}" "${5:-.github/workflows/presubmit.yaml}"
}
reset() { rm -f "$work/api/"* "$work/out" "$work/gho"; }

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() {
	printf '  ✗ %s\n' "$1" >&2
	fails=$((fails + 1))
}
run() {
	(cd "${dir:-$repo}" && env -u GITHUB_OUTPUT PATH="$work/bin:$PATH" GH_STUB_DIR="$work/api" \
		GITHUB_REPOSITORY=o/r WORKFLOW_PATH=.github/workflows/presubmit.yaml "$@" \
		bash "$SCRIPT" "${args[@]}" >"$work/out" 2>"$work/err")
}
said() { grep -qx "$1" "$work/out"; }

echo "tree"
args=(tree)
run
{ [ $? -eq 0 ] && said "tree=${tree}" && said "marker=${marker}" && ! grep -q '^verdict=' "$work/out"; } &&
	pass "prints the tree hash and the marker name, no verdict" || fail "got: $(cat "$work/out")"
[ ! -e "$work/api/calls" ] && pass "asks GitHub nothing" || fail "called gh"

echo "lookup: hit"
reset
artifacts "{\"artifacts\":[$(artifact 1 100)]}"
run_json 100 "$(good_run 100)"
args=(lookup presubmit)
run
{ [ $? -eq 0 ] && said "verdict=hit" && said "run=100"; } &&
	pass "a passed pull_request run on the same tree is a hit" || fail "got: $(cat "$work/out") $(cat "$work/err")"
: >"$work/gho"
run GITHUB_OUTPUT="$work/gho"
{ grep -qx "verdict=hit" "$work/gho" && grep -qx "tree=${tree}" "$work/gho"; } &&
	pass "writes the same lines to GITHUB_OUTPUT" || fail "GITHUB_OUTPUT: $(cat "$work/gho")"
reset
artifacts "{\"artifacts\":[$(artifact 1 100),$(artifact 2 200)]}"
run_json 100 "$(good_run 100)"
run_json 200 "$(good_run 200 pull_request failure)"
run
{ said "verdict=hit" && said "run=100"; } &&
	pass "a newer failed run does not hide an older passed one" || fail "got: $(cat "$work/out")"

echo "lookup: doubt is a miss"
miss() { # description
	run
	{ [ $? -eq 0 ] && said "verdict=miss" && said "run="; } && pass "$1" || fail "$1: got $(cat "$work/out")"
}
reset
miss "GitHub unreachable"
reset
artifacts '{"artifacts":[]}'
miss "no marker for this tree"
reset
artifacts 'not json'
miss "unreadable artifact list"
reset
artifacts "{\"artifacts\":[$(artifact 1 100 7 true)]}"
run_json 100 "$(good_run 100)"
miss "marker has expired"
reset
artifacts "{\"artifacts\":[$(artifact 1 100 99)]}"
run_json 100 "$(good_run 100)"
miss "marker was uploaded by a fork's run"
reset
artifacts "{\"artifacts\":[$(artifact 1 100)]}"
miss "the run behind the marker cannot be read"
for c in "merge_group success" "push success" "pull_request failure" "pull_request cancelled" "pull_request null"; do
	reset
	artifacts "{\"artifacts\":[$(artifact 1 100)]}"
	# shellcheck disable=SC2086
	run_json 100 "$(good_run 100 $c)"
	miss "run is '$c'"
done
reset
artifacts "{\"artifacts\":[$(artifact 1 100)]}"
run_json 100 "$(good_run 100 pull_request success someone/fork)"
miss "run's head repository is a fork"
reset
artifacts "{\"artifacts\":[$(artifact 1 100)]}"
run_json 100 "$(good_run 100 pull_request success o/r .github/workflows/other.yaml)"
miss "run is of a different workflow"
reset
artifacts "{\"artifacts\":[$(artifact 1 100 | sed "s/${marker}/${marker}x/")]}"
run_json 100 "$(good_run 100)"
miss "artifact with a different name in the reply is ignored"

echo "lookup: a different tree does not match"
echo two >"$repo/f"
git -C "$repo" commit -q -am c2
reset
artifacts "{\"artifacts\":[$(artifact 1 100)]}"
run_json 100 "$(good_run 100)"
miss "after the files change, the old marker is not found"
grep -q "passed-presubmit-$(git -C "$repo" rev-parse 'HEAD^{tree}')" "$work/api/calls" &&
	pass "it asked for the new tree's marker" || fail "asked: $(cat "$work/api/calls")"

echo "bad input"
dir="$work"
args=(lookup presubmit)
run
{ [ $? -eq 0 ] && said "verdict=miss" && said "tree="; } &&
	pass "outside a git repository: miss, exit 0" || fail "got: $(cat "$work/out")"
dir=""
args=(lookup 'bad name;rm')
run
[ $? -eq 2 ] && pass "refuses a check name that is not a plain slug" || fail "accepted a bad check name"
args=(nonsense)
run
[ $? -eq 2 ] && pass "refuses an unknown mode" || fail "accepted an unknown mode"

echo
if [ "$fails" -gt 0 ]; then
	echo "$fails check(s) FAILED" >&2
	exit 1
fi
echo "all queue-fast-pass checks passed"
