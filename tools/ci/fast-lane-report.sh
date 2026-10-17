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

# The weekly numbers for the agent fast lane (#3418, Step 2b): is skipping
# the PR's heavy tests costing us in the merge queue?
#
# For pull requests merged in the last N days (default 7), split into those
# with the agent-fast-lane label and all others:
#   - how many had at least one failed merge-queue run (Presubmit or CI);
#   - open -> merged time, median and 90th percentile;
#   - wall-clock minutes of their pull_request runs of Presubmit and CI. Not
#     billed runner minutes: run start to last update, as in the baseline.
# Then every fast-lane PR that failed in the queue, so each can be noted on
# #3418 with whether a PR run would have caught it.
#
# Read-only. Usage: fast-lane-report.sh [days]   Env: GH_TOKEN, REPO (default
# VitruvianSoftware/vitruvian-core).
set -euo pipefail

days="${1:-7}"
[[ "${days}" =~ ^[0-9]+$ ]] || {
	echo "usage: fast-lane-report.sh [days]" >&2
	exit 2
}
repo="${REPO:-VitruvianSoftware/vitruvian-core}"
since="$(date -u -v-"${days}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "${days} days ago" +%Y-%m-%dT%H:%M:%SZ)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

gh pr list --repo "${repo}" --state merged --limit 1000 --search "merged:>=${since%%T*}" \
	--json number,headRefName,labels,createdAt,mergedAt >"$tmp/prs.json"

runs() { # event -> one JSON array of {name, event, conclusion, branch, minutes}
	gh api --paginate "repos/${repo}/actions/runs?event=$1&created=>=${since}&per_page=100" \
		--jq '.workflow_runs[] | select(.name == "Presubmit" or .name == "CI")
		      | {name, conclusion, branch: .head_branch,
		         minutes: (((.updated_at | fromdate) - (.run_started_at | fromdate)) / 60)}' |
		jq -s .
}
runs merge_group >"$tmp/queue.json"
runs pull_request >"$tmp/pr-runs.json"

jq --slurpfile queue "$tmp/queue.json" --slurpfile prruns "$tmp/pr-runs.json" '
	($queue[0] | map(select(.conclusion == "failure")
	   | (.branch | capture("^gh-readonly-queue/main/pr-(?<n>[0-9]+)-").n | tonumber)) | unique) as $failed
	| map(. + {
	    fast: ([.labels[].name] | index("agent-fast-lane") != null),
	    queue_failed: (.number as $n | $failed | index($n) != null),
	    open_to_merged: (((.mergedAt | fromdate) - (.createdAt | fromdate)) / 60),
	    pr_minutes: (.headRefName as $b | [$prruns[0][] | select(.branch == $b) | .minutes] | add // 0)
	  })
' "$tmp/prs.json" >"$tmp/all.json"

jq -r '
	def pct(p): if length == 0 then "-" else (sort | .[((length - 1) * p | floor)] | floor | tostring) end;
	. as $all
	| (["group", "PRs", "queue-failed", "rate", "open->merged median (min)", "p90", "PR-lane CI min/PR"] | @tsv),
	  ([true, false][] as $f
	   | [$all[] | select(.fast == $f)] as $g
	   | [ (if $f then "agent-fast-lane" else "all others" end),
	       ($g | length),
	       ([$g[] | select(.queue_failed)] | length),
	       (if ($g | length) == 0 then "-" else "\(([$g[] | select(.queue_failed)] | length) * 1000 / ($g | length) | floor / 10)%" end),
	       ([$g[].open_to_merged] | pct(0.5)),
	       ([$g[].open_to_merged] | pct(0.9)),
	       (if ($g | length) == 0 then "-" else ([$g[].pr_minutes] | add / length | floor | tostring) end)
	     ] | @tsv)
' "$tmp/all.json" | column -t -s $'\t'
echo
echo "fast-lane PRs that failed in the merge queue (note each on #3418):"
jq -r '[.[] | select(.fast and .queue_failed) | "  #\(.number)"] | if length == 0 then ["  none"] else . end | .[]' "$tmp/all.json"
echo
echo "window: merged since ${since} (${days} days); CI minutes are wall-clock per run, not billed."
