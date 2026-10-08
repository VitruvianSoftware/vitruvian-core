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

# Claude Code PreToolUse hook (Bash): refuse commands that put a change on main
# without the merge queue.
#
# WHY. main's ruleset lets repository admins skip the merge queue, as a
# break-glass for the one human maintainer. Agent sessions act with that same
# account, so they inherit the bypass. On 2026-10-07/08 five of forty merges
# skipped the queue; one (#2881) had been rejected by the queue eight minutes
# earlier, and main went red. The break-glass is for a person deciding to use
# it, not for an agent that wants its PR to land.
#
# WHAT IT REFUSES
#   gh pr merge ... --admin               merge past required checks and the queue
#   gh api ... pulls/<n>/merge  (PUT)     the same thing through the REST API
#   gh api graphql ... mergePullRequest   the same thing through GraphQL
#   git push ... main                     a direct push to main
# `gh pr merge <n>` WITHOUT --admin is the normal path -- it adds the PR to the
# queue -- and is allowed.
#
# This is a guardrail against a habit, not a security boundary: it reads the
# command text. A human who needs the break-glass runs the command in their own
# terminal, where this hook does not apply.
#
# Input: the hook payload on stdin ({"tool_input":{"command":"..."}}).
# Output: nothing and exit 0 to allow; a permissionDecision "deny" JSON to refuse.
set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
	echo "block-queue-bypass: jq not found; not checking this command" >&2
	exit 0
fi

command_text="$(jq -r '.tool_input.command // ""' 2>/dev/null || true)"
[ -n "${command_text}" ] || exit 0

deny() {
	jq -n --arg why "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $why}}'
	exit 0
}

HOW="Add the PR to the merge queue instead (gh pr merge <number>, no --admin) and wait for it. If the queue rejected the PR, fix what failed. Skipping the queue is the human maintainer's break-glass: ask James, do not do it yourself."

# Look at each simple command on its own: split on newlines, ; && || | and $(, and
# drop leading whitespace, subshell openers and VAR=value prefixes. Text inside
# a quoted string or heredoc that does not START a line with one of these
# commands (a PR body that mentions them, say) is left alone.
while IFS= read -r segment; do
	segment="$(printf '%s' "${segment}" | sed -E 's/^[[:space:](]+//; s/^(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|command|exec|time)[[:space:]]+)+//')"
	case "${segment}" in
	"gh pr merge"*)
		if printf '%s' "${segment}" | grep -Eq '(^|[[:space:]])--admin([^[:alnum:]_-]|$)'; then
			deny "Refused: 'gh pr merge --admin' merges past the merge queue. ${HOW}"
		fi
		;;
	"gh api"*)
		if printf '%s' "${segment}" | grep -Eq 'pulls/[0-9]+/merge' &&
			printf '%s' "${segment}" | grep -Eiq '(-X|--method)[[:space:]=]*PUT'; then
			deny "Refused: this API call merges a pull request directly, past the merge queue. ${HOW}"
		fi
		if printf '%s' "${segment}" | grep -q 'mergePullRequest'; then
			deny "Refused: the mergePullRequest mutation merges directly, past the merge queue. ${HOW}"
		fi
		;;
	"git push"* | "git -C "*" push"*)
		# A refspec whose destination is main: `main`, `x:main`, `refs/heads/main`.
		if printf '%s' "${segment}" | grep -Eq '(^|[[:space:]:+])(refs/heads/)?main([[:space:])]|$)'; then
			deny "Refused: this pushes straight to main, past the merge queue. Push a branch and open a pull request. ${HOW}"
		fi
		;;
	esac
done < <(printf '%s\n' "${command_text}" | sed -E 's/(&&|\|\||;|\||[$][(])/\n/g')

exit 0
