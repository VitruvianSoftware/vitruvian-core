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

# Decides one thing for a pull request: may it skip the heavy test and build
# jobs? (#3418, Step 2b)
#
# WHY. Agent PRs are tested three times today: on the PR, in the merge queue,
# and (until Step 1) on main. The merge queue runs every test on the exact
# code that will land, so a PR run only finds a problem a little earlier. For
# our own agents' PRs we try going without it and measure what it costs in
# queue failures.
#
# WHO. All of these, or nobody:
#   - a pull_request event;
#   - from a branch in this repository, not a fork;
#   - opened by one of our agent apps: the author is a Bot whose user id is in
#     tools/agent-app/agents.tsv (the id, not the name, which anyone can copy);
#   - carrying the `agent-fast-lane` label.
# The fast checks (secret scan, licence, vulnerability scan, conformance,
# tidy, naming, actionlint) never ask this script and always run.
#
# Callers run this script and agents.tsv from the BASE branch, not from the
# PR, so a pull request cannot rewrite the rule that lets it skip its tests.
#
# Any doubt is "full": a missing or unreadable roster, an unexpected event,
# a malformed label list. Full means the PR runs everything, as before.
#
# Prints verdict=fast|full and reason=..., also appended to $GITHUB_OUTPUT.
#
# Env: EVENT_NAME, GITHUB_REPOSITORY, PR_HEAD_REPO, PR_AUTHOR_ID,
# PR_AUTHOR_TYPE, PR_LABELS (JSON array of label names), AGENTS_TSV (path).
set -uo pipefail

LABEL="agent-fast-lane"

emit() {
	echo "$1"
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		echo "$1" >>"${GITHUB_OUTPUT}"
	fi
}

finish() {
	emit "verdict=$1"
	emit "reason=$2"
	echo "agent-fast-lane: $1: $2" >&2
	exit 0
}

[ "${EVENT_NAME:-}" = pull_request ] || finish full "not a pull request"
repo="${GITHUB_REPOSITORY:-}"
[ -n "${repo}" ] || finish full "GITHUB_REPOSITORY is not set"
[ "${PR_HEAD_REPO:-}" = "${repo}" ] || finish full "the branch is not in ${repo} (a fork?)"

if ! labelled="$(jq -r --arg l "${LABEL}" 'if type == "array" then any(.[]; . == $l) else error("not a list") end' <<<"${PR_LABELS:-}" 2>/dev/null)"; then
	finish full "could not read the label list"
fi
[ "${labelled}" = true ] || finish full "no ${LABEL} label"

[ "${PR_AUTHOR_TYPE:-}" = Bot ] || finish full "opened by a person, not an agent app"
id="${PR_AUTHOR_ID:-}"
[[ "${id}" =~ ^[0-9]+$ ]] || finish full "no author id"

roster="${AGENTS_TSV:-}"
[ -f "${roster}" ] || finish full "agent roster not found"
# agent  app_id  installation_id  bot_user_id; comments and blank lines skipped.
if ! agent="$(awk -F'\t' -v id="${id}" '!/^#/ && NF >= 4 && $4 == id { print $1; exit }' "${roster}")"; then
	finish full "could not read the agent roster"
fi
[ -n "${agent}" ] || finish full "author ${id} is not one of the agent apps"

finish fast "opened by the ${agent} agent app from a branch in ${repo}, with the ${LABEL} label"
