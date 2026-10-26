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
SCRIPT="${1:-${HERE}/queue-fast-pass.sh}"
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"

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
invoke() {
	if [[ "$SCRIPT" == *.sh ]]; then bash "$SCRIPT" "$@"
	else "$SCRIPT" "$@"; fi
}
export -f invoke
export SCRIPT
run() {
	(cd "${dir:-$repo}" && env -u GITHUB_OUTPUT PATH="$work/bin:$PATH" GH_STUB_DIR="$work/api" \
		GITHUB_REPOSITORY=o/r WORKFLOW_PATH=.github/workflows/presubmit.yaml "$@" \
		bash -c 'invoke "$@"' _ "${args[@]}" >"$work/out" 2>"$work/err")
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

echo "queued: a push to main the merge queue already passed"
# The queue squash-merges, so the commit that lands has the tree its
# merge_group run tested. HEAD is c2 here; c1 is main before the push.
before="$(git -C "$repo" rev-parse HEAD~1)"
head="$(git -C "$repo" rev-parse HEAD)"
qtree="$(git -C "$repo" rev-parse 'HEAD^{tree}')"
compare_path="repos/o/r/compare/${before}...${head}"
runs_path="repos/o/r/actions/workflows/presubmit.yaml/runs?event=merge_group&status=success&per_page=30"
changed() { # file...
	local list=""
	for f in "$@"; do list="${list:+${list},}{\"filename\":\"${f}\"}"; done
	printf '{"files":[%s]}' "${list}" >"$work/api/$(key "$compare_path")"
}
queue_runs() { printf '{"workflow_runs":[%s]}' "$1" >"$work/api/$(key "$runs_path")"; }
queue_run() { # id tree [event] [conclusion] [repo] [path]
	printf '{"id":%s,"event":"%s","conclusion":"%s","head_repository":{"full_name":"%s"},"path":"%s","head_commit":{"tree_id":"%s"}}' \
		"$1" "${3:-merge_group}" "${4:-success}" "${5:-o/r}" "${6:-.github/workflows/presubmit.yaml}" "$2"
}
args=(queued)
qrun() { run PUSH_BEFORE="${push_before-$before}" FORCED_PUSH="${forced:-false}"; }
qmiss() { # description
	qrun
	{ [ $? -eq 0 ] && said "verdict=miss" && said "run="; } && pass "$1" || fail "$1: got $(cat "$work/out") $(cat "$work/err")"
}

reset
changed apps/web/page.ts
queue_runs "$(queue_run 300 "$qtree")"
qrun
{ [ $? -eq 0 ] && said "verdict=hit" && said "run=300"; } &&
	pass "a green merge_group run on the same tree skips the re-test" || fail "got: $(cat "$work/out") $(cat "$work/err")"
reset
changed apps/web/page.ts
queue_runs "$(queue_run 301 0000000000000000000000000000000000000001),$(queue_run 300 "$qtree")"
qrun
{ said "verdict=hit" && said "run=300"; } &&
	pass "a newer queue run on other code does not hide the matching one" || fail "got: $(cat "$work/out")"
reset
changed apps/web/page.ts
queue_runs "$(queue_run 300 "$qtree")"
run PUSH_BEFORE="$before" WORKFLOW_PATH=.github/workflows/ci.yaml
{ said "verdict=miss" && grep -q 'workflows/ci.yaml/runs' "$work/api/calls" 2>/dev/null; } &&
	pass "asks about the calling workflow, and a Presubmit run does not count for CI" || fail "got: $(cat "$work/out"); asked: $(cat "$work/api/calls")"

echo "queued: anything else runs everything"
reset
changed apps/web/page.ts
queue_runs ""
qmiss "no merge queue run at all (a direct push)"
reset
changed apps/web/page.ts
queue_runs "$(queue_run 300 0000000000000000000000000000000000000001)"
qmiss "the queue tested different code"
for c in "push success" "pull_request success" "merge_group failure" "merge_group cancelled" "merge_group null"; do
	reset
	changed apps/web/page.ts
	# shellcheck disable=SC2086
	queue_runs "$(queue_run 300 "$qtree" $c)"
	qmiss "the matching run is '$c'"
done
reset
changed apps/web/page.ts
queue_runs "$(queue_run 300 "$qtree" merge_group success someone/fork)"
qmiss "the matching run came from a fork"
reset
changed apps/web/page.ts
queue_runs "$(queue_run 300 "$qtree" merge_group success o/r .github/workflows/other.yaml)"
qmiss "the matching run is of another workflow"
reset
changed apps/web/page.ts
qmiss "the queue runs cannot be listed"
reset
queue_runs "$(queue_run 300 "$qtree")"
qmiss "the changed files cannot be listed"
reset
printf '{"files":[%s{"filename":"last"}]}' "$(for _ in $(seq 300); do printf '{"filename":"x"},'; done)" >"$work/api/$(key "$compare_path")"
queue_runs "$(queue_run 300 "$qtree")"
qmiss "300 or more changed files (the list may be cut short)"
for f in MODULE.bazel MODULE.bazel.lock .bazelversion .bazelrc go.sum apps/cli/devx/go.mod go.work.sum .xcode-version apps/cli/devx/.golangci.yml; do
	reset
	changed docs/a.md "$f"
	queue_runs "$(queue_run 300 "$qtree")"
	qmiss "the push changed ${f}, which a main-only cache is keyed on"
done
reset
changed apps/web/page.ts
queue_runs "$(queue_run 300 "$qtree")"
forced=true qmiss "a forced push"
reset
changed apps/web/page.ts
queue_runs "$(queue_run 300 "$qtree")"
push_before=0000000000000000000000000000000000000000 qmiss "main was just created (before is all zeros)"
push_before="" qmiss "no before commit"
reset
changed apps/web/page.ts
queue_runs "$(queue_run 300 "$qtree")"
run PUSH_BEFORE="$before" WORKFLOW_PATH='../../etc/passwd'
said "verdict=miss" && ! grep -qs "actions/workflows" "$work/api/calls" &&
	pass "refuses a WORKFLOW_PATH that is not a workflow file" || fail "got: $(cat "$work/out")"

echo "queued: ci.yaml waits on the lookup the safe way"
# Every job in CI must skip on a hit and must still run when the lookup job
# itself is skipped, which it is on every pull request and in the queue. A job
# that needs `queued` without !cancelled() or always() would be skipped there
# too, and GitHub counts a skipped required check as passing: that change
# would never be tested. (A job that forgets the hit check only wastes a run.)
ci="${HERE}/../../.github/workflows/ci.yaml"
jobs="$(awk '
	/^jobs:/ { in_jobs = 1; next }
	!in_jobs { next }
	/^  [A-Za-z0-9_-]+:$/ { if (job != "") print job "\t" needs "\t" cond; job = substr($1, 1, length($1) - 1); needs = ""; cond = ""; in_if = 0; next }
	/^    needs:/ { needs = $0; in_if = 0; next }
	/^    if:/ { cond = $0; in_if = 1; next }
	in_if && /^      / { cond = cond " " $0; next }
	/^    [a-z]/ { in_if = 0 }
	END { if (job != "") print job "\t" needs "\t" cond }
' "$ci")"
count=0
while IFS=$'\t' read -r job needs cond; do
	case "$job" in queued | fast-lane) continue ;; esac
	count=$((count + 1))
	why=""
	[[ "$needs" =~ (^|[^a-z-])queued([^a-z-]|$) ]] || why="does not need queued"
	[[ "$cond" == *"needs.queued.outputs.hit != 'true'"* ]] || why="${why:+$why; }does not skip on a hit"
	[[ "$cond" == *'!cancelled()'* || "$cond" == *'always()'* ]] || why="${why:+$why; }would be skipped whenever queued is skipped"
	[ -z "$why" ] && pass "ci.yaml job ${job}" || fail "ci.yaml job ${job}: ${why}"
done <<<"$jobs"
[ "$count" -ge 10 ] && pass "read ${count} ci.yaml jobs" || fail "read only ${count} ci.yaml jobs; the parser is out of date"

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
