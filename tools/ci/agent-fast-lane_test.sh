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

# Guard for tools/ci/agent-fast-lane.sh (#3418, Step 2b), and for how ci.yaml
# uses it. The point of most cases is that only one exact combination skips
# the heavy jobs; everything else runs them.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$(cd "$(dirname "${1:-${HERE}/agent-fast-lane.sh}")" && pwd)/$(basename "${1:-${HERE}/agent-fast-lane.sh}")"
ROSTER="${HERE}/../agent-app/agents.tsv"
CI="${HERE}/../../.github/workflows/ci.yaml"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() {
	printf '  ✗ %s\n' "$1" >&2
	fails=$((fails + 1))
}

# A real agent's bot user id, read from the real roster, so the test follows it.
agent_id="$(awk -F'\t' '!/^#/ && NF >= 4 { print $4; exit }' "$ROSTER")"
[[ "$agent_id" =~ ^[0-9]+$ ]] || {
	echo "could not read an agent id from $ROSTER" >&2
	exit 1
}

# decide [VAR=value ...]: an agent PR from this repo with the label, unless a
# VAR=value overrides one part of it.
decide() {
	if [[ "$SCRIPT" == *.sh ]]; then
		env -u GITHUB_OUTPUT EVENT_NAME=pull_request GITHUB_REPOSITORY=o/r PR_HEAD_REPO=o/r \
			PR_AUTHOR_TYPE=Bot PR_AUTHOR_ID="$agent_id" PR_LABELS='["ci","agent-fast-lane"]' \
			AGENTS_TSV="$ROSTER" "$@" bash "$SCRIPT" >"$work/out" 2>"$work/err"
	else
		env -u GITHUB_OUTPUT EVENT_NAME=pull_request GITHUB_REPOSITORY=o/r PR_HEAD_REPO=o/r \
			PR_AUTHOR_TYPE=Bot PR_AUTHOR_ID="$agent_id" PR_LABELS='["ci","agent-fast-lane"]' \
			AGENTS_TSV="$ROSTER" "$@" "$SCRIPT" >"$work/out" 2>"$work/err"
	fi
}
said() { grep -qx "$1" "$work/out"; }
full() { # description, VAR=value ...
	local what="$1"
	shift
	decide "$@"
	{ [ $? -eq 0 ] && said "verdict=full"; } && pass "$what" || fail "$what: got $(cat "$work/out")"
}

echo "the one case that skips"
decide
{ [ $? -eq 0 ] && said "verdict=fast"; } && pass "an agent PR from this repo with the label is fast" ||
	fail "got: $(cat "$work/out") $(cat "$work/err")"
: >"$work/gho"
decide GITHUB_OUTPUT="$work/gho"
grep -qx "verdict=fast" "$work/gho" && pass "writes the verdict to GITHUB_OUTPUT" || fail "GITHUB_OUTPUT: $(cat "$work/gho")"

echo "everything else runs in full"
full "a fork PR with the label" PR_HEAD_REPO=someone/r
full "a PR opened by a person, with the label" PR_AUTHOR_TYPE=User PR_AUTHOR_ID=3703513
full "a person whose user id happens to match an agent's" PR_AUTHOR_TYPE=User
full "a bot that is not one of our agents" PR_AUTHOR_ID=49699333
full "an agent PR without the label" PR_LABELS='["ci"]'
full "an agent PR with no labels at all" PR_LABELS='[]'
full "a label that only looks similar" PR_LABELS='["agent-fast-lane-x","Agent-Fast-Lane"]'
full "a merge_group event" EVENT_NAME=merge_group
full "a push event" EVENT_NAME=push
full "an unreadable label list" PR_LABELS='not json'
full "a label list that is not a list" PR_LABELS='"agent-fast-lane"'
full "an empty label list value" PR_LABELS=
full "no author id" PR_AUTHOR_ID=
full "an author id that is not a number" PR_AUTHOR_ID='1 OR 1'
full "the roster is missing" AGENTS_TSV="$work/nope.tsv"
printf '# agent\tapp_id\tinstallation_id\tbot_user_id\n#x\t1\t2\t%s\n' "$agent_id" >"$work/commented.tsv"
full "an id that appears only in a comment line" AGENTS_TSV="$work/commented.tsv"
full "GITHUB_REPOSITORY unset" GITHUB_REPOSITORY=

echo "ci.yaml: heavy jobs skip on the fast lane, the fast checks never do"
# One line per job: name, needs line, if condition (folded onto one line).
jobs="$(awk '
	/^jobs:/ { in_jobs = 1; next }
	!in_jobs { next }
	/^  [A-Za-z0-9_-]+:$/ { if (job != "") print job "\t" needs "\t" cond; job = substr($1, 1, length($1) - 1); needs = ""; cond = ""; in_if = 0; next }
	/^    needs:/ { needs = $0; in_if = 0; next }
	/^    if:/ { cond = $0; in_if = 1; next }
	in_if && /^      / { cond = cond " " $0; next }
	/^    [a-z]/ { in_if = 0 }
	END { if (job != "") print job "\t" needs "\t" cond }
' "$CI")"
# The fast checks that live in ci.yaml. The rest (secret scan, osv-scan,
# conformance, tidy, actionlint) are other workflows and never see the label.
fast_checks=" license-check lint-naming "
count=0
while IFS=$'\t' read -r job needs cond; do
	case "$job" in queued | fast-lane) continue ;; esac
	count=$((count + 1))
	if [[ "$fast_checks" == *" $job "* ]]; then
		[[ "$needs$cond" != *fast-lane* ]] && pass "fast check ${job} ignores the fast lane" ||
			fail "fast check ${job} must always run on a PR, but it reads fast-lane"
		continue
	fi
	why=""
	[[ "$needs" =~ (^|[^a-z-])fast-lane([^a-z-]|$) ]] || why="does not need fast-lane"
	[[ "$cond" == *"needs.fast-lane.outputs.skip != 'true'"* ]] || why="${why:+$why; }does not skip on the fast lane"
	[[ "$cond" == *'!cancelled()'* || "$cond" == *'always()'* ]] || why="${why:+$why; }would be skipped whenever fast-lane is skipped"
	[ -z "$why" ] && pass "heavy job ${job} skips on the fast lane" || fail "heavy job ${job}: ${why}"
done <<<"$jobs"
[ "$count" -ge 10 ] && pass "read ${count} ci.yaml jobs" || fail "read only ${count} ci.yaml jobs; the parser is out of date"

# The fast-lane job decides with main's copy of the script and roster.
fl="$(awk '/^  fast-lane:$/ { on = 1; next } on && /^  [A-Za-z0-9_-]+:$/ { exit } on' "$CI")"
grep -q "ref: \${{ github.event.pull_request.base.sha }}" <<<"$fl" &&
	pass "fast-lane checks out the base branch, not the PR" || fail "fast-lane must check out the PR's base commit"
grep -q "if: github.event_name == 'pull_request' && contains(github.event.pull_request.labels.\*.name, 'agent-fast-lane')" <<<"$fl" &&
	pass "fast-lane takes a runner only for a labelled PR" || fail "fast-lane must be skipped unless the PR has the label"

echo
if [ "$fails" -gt 0 ]; then
	echo "$fails check(s) FAILED" >&2
	exit 1
fi
echo "all agent-fast-lane checks passed"
