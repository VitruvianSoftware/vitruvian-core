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

# Asks one question for the merge queue: has this exact code already passed
# this check on its pull request? (#2841)
#
# WHY. The queue re-tests every PR on top of the newest main. When main has
# not moved since the PR's own checks ran, the queue's trial commit holds the
# very same files the PR run already tested, and the re-test can only repeat
# the answer (or trip over a flaky test). A replay of 103 queue entries on
# 2026-10-07..09 found 23 such entries; five checked by hand all matched.
#
# HOW. "The same files" is decided by git's tree hash of HEAD, which is equal
# exactly when every file is byte-for-byte equal, however the commit was made.
# A PR run that passes uploads an artifact named passed-<check>-<tree>.
# `lookup` in the queue looks for that name and then confirms the run behind
# it: same repository (not a fork), a pull_request run of the expected
# workflow, concluded success.
#
# It never fails the job and never says "hit" on doubt: any error, any field
# that does not match, is a miss, and a miss means "run the tests as usual".
#
# A second question, for a push to main (#3418): did the merge queue already
# pass this workflow on this exact code? The queue squash-merges, so the
# commit that lands on main has the same tree its merge_group run tested, and
# re-testing it can only repeat the answer or trip over a flaky test. `queued`
# lists this workflow's newest successful merge_group runs and looks for one
# whose head commit has HEAD's tree. Same rule: doubt is a miss, and a miss
# runs everything as before. A direct push, or a queue run that went red or
# never happened, finds nothing.
#
# It also misses when the push changes a file that GitHub Actions cache keys
# are built from (MODULE.bazel, go.sum, ...). Those caches live per branch:
# one saved by a queue run sits on the queue's temporary branch, where pull
# requests cannot read it. Only a run on main saves them where pull requests
# look, and they are saved only when the key moves, so that push runs in
# full. CACHE_KEY_REGEX overrides the list.
#
# Usage:
#   queue-fast-pass.sh tree              print tree= and marker= for HEAD
#   queue-fast-pass.sh lookup <check>    also print verdict=hit|miss, run=, reason=
#   queue-fast-pass.sh queued            the same three, for a push to main
#
# Every line printed to stdout is also appended to $GITHUB_OUTPUT when set.
#
# Env: GH_TOKEN (needs actions: read), GITHUB_REPOSITORY, WORKFLOW_PATH
# (optional for lookup, required for queued, e.g.
# .github/workflows/presubmit.yaml: the run must be of it). queued also reads
# PUSH_BEFORE (main's commit before the push) and FORCED_PUSH.
set -uo pipefail

log() { echo "queue-fast-pass: $*" >&2; }

emit() {
	echo "$1"
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		echo "$1" >>"${GITHUB_OUTPUT}"
	fi
}

finish() {
	emit "verdict=$1"
	emit "run=${3:-}"
	emit "reason=$2"
	log "$1: $2"
	exit 0
}

mode="${1:-}"
check="${2:-}"
case "${mode}" in
tree) check="${check:-presubmit}" ;;
lookup) ;;
queued) check=presubmit ;;
*)
	log "usage: queue-fast-pass.sh tree | lookup <check> | queued"
	exit 2
	;;
esac
if ! [[ "${check}" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
	log "check name must be lowercase letters, digits and dashes, got '${check}'"
	exit 2
fi

tree="$(git rev-parse --verify --quiet 'HEAD^{tree}' 2>/dev/null)" || tree=""
if ! [[ "${tree}" =~ ^[0-9a-f]{40,64}$ ]]; then
	emit "tree="
	emit "marker="
	[ "${mode}" = tree ] && exit 0
	finish miss "could not read the tree hash of HEAD"
fi
marker="passed-${check}-${tree}"
emit "tree=${tree}"
emit "marker=${marker}"
[ "${mode}" = tree ] && exit 0

repo="${GITHUB_REPOSITORY:-}"
[ -n "${repo}" ] || finish miss "GITHUB_REPOSITORY is not set"

if [ "${mode}" = queued ]; then
	path="${WORKFLOW_PATH:-}"
	[[ "${path}" =~ ^\.github/workflows/[A-Za-z0-9._-]+\.ya?ml$ ]] || finish miss "WORKFLOW_PATH is not a workflow file"
	[ "${FORCED_PUSH:-false}" != true ] || finish miss "a forced push rewrote main's history"
	before="${PUSH_BEFORE:-}"
	[[ "${before}" =~ ^[0-9a-f]{40,64}$ ]] && [[ "${before}" =~ [1-9a-f] ]] ||
		finish miss "no commit before this push to compare with"
	head="$(git rev-parse --verify --quiet HEAD 2>/dev/null)" || finish miss "could not read HEAD"

	# The files this push changed. The compare reply lists at most 300; a
	# longer list could hide a cache-key file, so it counts as doubt.
	if ! files="$(gh api "repos/${repo}/compare/${before}...${head}" 2>/dev/null |
		jq -er 'if (.files | length) >= 300 then error("too many") else .files[].filename end' 2>/dev/null)"; then
		finish miss "could not list the files this push changed"
	fi
	keys="${CACHE_KEY_REGEX:-(^|/)(MODULE\.bazel(\.lock)?|\.bazelversion|\.bazelrc|go\.(mod|sum|work|work\.sum)|\.xcode-version|\.golangci\.ya?ml)$}"
	if hit_file="$(grep -m1 -E "${keys}" <<<"${files}")"; then
		finish miss "${hit_file} changed, and caches keyed on it are saved only by a full run on main"
	fi

	if ! found="$(gh api "repos/${repo}/actions/workflows/${path##*/}/runs?event=merge_group&status=success&per_page=30" 2>/dev/null)"; then
		finish miss "could not list merge queue runs"
	fi
	# A queue run counts only when it is this repository's own code, of this
	# workflow, finished green, and its head commit has exactly HEAD's tree.
	if ! id="$(jq -r --arg tree "${tree}" --arg repo "${repo}" --arg path "${path}" '
		[.workflow_runs[]?
		 | select(.event == "merge_group" and .conclusion == "success")
		 | select(.head_repository.full_name == $repo and .path == $path)
		 | select(.head_commit.tree_id == $tree)]
		| first | .id // ""' <<<"${found}" 2>/dev/null)"; then
		finish miss "could not read the merge queue runs"
	fi
	[[ "${id}" =~ ^[0-9]+$ ]] || finish miss "no green merge queue run of ${path##*/} on this exact tree"
	finish hit "merge queue run ${id} passed ${path##*/} on this exact tree" "${id}"
fi

if ! found="$(gh api "repos/${repo}/actions/artifacts?name=${marker}&per_page=30" 2>/dev/null)"; then
	finish miss "could not list artifacts"
fi
# Newest first; only markers that still exist and were uploaded by a run of
# this repository's own code (a fork's run has a different head repository).
if ! runs="$(jq -r --arg name "${marker}" '
	[.artifacts[]?
	 | select(.name == $name and .expired == false)
	 | select(.workflow_run.id != null)
	 | select(.workflow_run.head_repository_id == .workflow_run.repository_id)]
	| sort_by(.created_at) | reverse | .[].workflow_run.id' <<<"${found}" 2>/dev/null)"; then
	finish miss "could not read the artifact list"
fi
[ -n "${runs}" ] || finish miss "no earlier run passed ${check} on this exact tree"

why="no matching run"
for id in ${runs}; do
	[[ "${id}" =~ ^[0-9]+$ ]] || continue
	if ! run="$(gh api "repos/${repo}/actions/runs/${id}" 2>/dev/null)"; then
		why="could not read run ${id}"
		continue
	fi
	bad="$(jq -r --arg repo "${repo}" --arg path "${WORKFLOW_PATH:-}" '
		if .event != "pull_request" then "run \(.id) is a \(.event) run, not a pull_request run"
		elif .conclusion != "success" then "run \(.id) concluded \(.conclusion // "nothing yet")"
		elif .head_repository.full_name != $repo then "run \(.id) came from a fork"
		elif $path != "" and .path != $path then "run \(.id) is of \(.path), not \($path)"
		else "" end' <<<"${run}" 2>/dev/null)" || bad="could not read run ${id}"
	if [ -z "${bad}" ]; then
		finish hit "run ${id} passed ${check} on this exact tree" "${id}"
	fi
	why="${bad}"
done
finish miss "${why}"
