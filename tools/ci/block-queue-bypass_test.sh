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

# Guard for .claude/block-queue-bypass.sh, the Claude Code hook that refuses
# commands which land a change on main without the merge queue. Feeds it the
# same JSON payload Claude Code sends and checks the decision. Also checks the
# hook is actually wired into .claude/settings.json -- a correct script that
# nothing calls protects nothing.

set -uo pipefail

ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
HOOK="${ROOT}/.claude/block-queue-bypass.sh"
SETTINGS="${ROOT}/.claude/settings.json"

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }

# decision <command text>: "deny" or "allow".
decision() {
  local out
  out="$(printf '%s' "$1" | jq -Rs '{tool_name: "Bash", tool_input: {command: .}}' | bash "${HOOK}")" || { echo "error"; return; }
  if [ -z "${out}" ]; then echo allow; else printf '%s' "${out}" | jq -r '.hookSpecificOutput.permissionDecision'; fi
}
expect() { # <deny|allow> <label> <command>
  local got; got="$(decision "$3")"
  [ "${got}" = "$1" ] && pass "$1: $2" || fail "$2 -> got ${got}, want $1: $3"
}

echo "refused: ways past the merge queue"
expect deny  "gh pr merge --admin"                      'gh pr merge 2881 --admin --squash'
expect deny  "--admin anywhere in the command"          'gh pr merge --squash --admin 2881 -R VitruvianSoftware/vitruvian-core'
expect deny  "after cd &&"                              'cd /tmp/x && gh pr merge 5 --admin'
expect deny  "on a later line"                          $'echo start\ngh pr merge 5 --admin\necho done'
expect deny  "with an env prefix"                       'GH_TOKEN=abc gh pr merge 5 --admin'
expect deny  "inside \$( )"                             'out=$(gh pr merge 5 --admin)'
expect deny  "REST merge, -X PUT"                       'gh api -X PUT repos/o/r/pulls/12/merge -f merge_method=squash'
expect deny  "REST merge, --method PUT"                 'gh api --method PUT repos/o/r/pulls/12/merge'
expect deny  "GraphQL mergePullRequest"                 'gh api graphql -f query="mutation { mergePullRequest(input: {pullRequestId: \"x\"}) { clientMutationId } }"'
expect deny  "push to main"                             'git push origin main'
expect deny  "push HEAD:main"                           'git push origin HEAD:main'
expect deny  "push to refs/heads/main"                  'git push origin fix/thing:refs/heads/main'
expect deny  "forced push to main"                      'git push --force origin +HEAD:main'
expect deny  "git -C <dir> push main"                   'git -C /repo push origin main'

echo "allowed: the normal path and look-alikes"
expect allow "gh pr merge (adds to the queue)"          'gh pr merge 2885 -R VitruvianSoftware/vitruvian-core --squash'
expect allow "reading a PR's merge status"              'gh api repos/o/r/pulls/12/merge'
expect allow "GraphQL enqueuePullRequest"               'gh api graphql -f query="mutation { enqueuePullRequest(input: {pullRequestId: \"x\"}) { clientMutationId } }"'
expect allow "push a branch"                            'git push -u origin ci/some-branch'
expect allow "branch name ending in /main"              'git push origin fix/main'
expect allow "branch name starting with main"           'git push origin main-menu-fix'
expect allow "fetch main"                               'git fetch origin main'
expect allow "a PR body that mentions the command"      $'gh pr create --title x --body-file - <<\'B\'\nNever run `gh pr merge --admin` on this repo.\nB'
expect allow "unrelated command"                        'bazel test //...'
expect allow "empty command"                            ''

echo "payload handling"
out="$(printf 'not json' | bash "${HOOK}")"; rc=$?
{ [ "${rc}" -eq 0 ] && [ -z "${out}" ]; } && pass "unreadable payload: allows, exits 0" || fail "unreadable payload: rc=${rc} out=${out}"
why="$(printf '%s' 'gh pr merge 1 --admin' | jq -Rs '{tool_input: {command: .}}' | bash "${HOOK}" | jq -r '.hookSpecificOutput.permissionDecisionReason')"
case "${why}" in *"merge queue"*"gh pr merge <number>"*) pass "the refusal says what to do instead" ;; *) fail "unhelpful reason: ${why}" ;; esac

echo "wiring"
wired="$(jq -r '.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[] | select(.type == "command") | .command' "${SETTINGS}" 2>/dev/null)"
case "${wired}" in *".claude/block-queue-bypass.sh"*) pass "settings.json runs the hook before every Bash command" ;; *) fail "hook is not wired into .claude/settings.json: '${wired}'" ;; esac
[ -x "${HOOK}" ] && pass "hook script is executable" || fail "hook script is not executable"

echo
if [ "${fails}" -gt 0 ]; then echo "${fails} check(s) FAILED" >&2; exit 1; fi
echo "all block-queue-bypass checks passed"
