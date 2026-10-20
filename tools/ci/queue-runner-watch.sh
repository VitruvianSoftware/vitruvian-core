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

# queue-runner-watch — is the homelab runner pool taking jobs? If not, send the
# merge queue's jobs back to GitHub-hosted runners until it is.
#
# Runs in the queue-runner-watch workflow, which starts a one-step "canary" job
# on the homelab runners and this script on a hosted runner. After WAIT seconds
# the canary must be running or done: a canary still queued means no homelab
# runner took it (cluster down, power, network, controller), and a failed one
# means runners start but cannot run a job. Either way the repository variable
# QUEUE_RUNNER_FALLBACK is set to "on", which every routed workflow reads
# (spec §4): jobs then run on GitHub-hosted runners. A canary that runs flips
# it back to "off". The variable only changes when the answer does.
#
# Spec: docs/superpowers/specs/2026-10-19-queue-runners-on-homelab-design.md
#
# Env: REPO, RUN_ID (this workflow run), CANARY_JOB (job name, default
# "canary"), WAIT_SECONDS (default 180), GH_TOKEN (can write variables and
# cancel runs), GH_BIN (tests).
set -euo pipefail

GH="${GH_BIN:-gh}"
: "${REPO:?}" "${RUN_ID:?}"
JOB="${CANARY_JOB:-canary}"
VAR=QUEUE_RUNNER_FALLBACK

sleep "${WAIT_SECONDS:-180}"

state="$("$GH" api "repos/${REPO}/actions/runs/${RUN_ID}/jobs" \
  --jq ".jobs[] | select(.name == \"${JOB}\") | \"\\(.status) \\(.conclusion // \"\")\"")"
[ -n "$state" ] || { echo "queue-runner-watch: no job named '${JOB}' in run ${RUN_ID}" >&2; exit 1; }
status="${state%% *}"
conclusion="${state#* }"

case "$status:$conclusion" in
  in_progress:* | completed:success)
    want=off
    why="the canary $status${conclusion:+ ($conclusion)}: homelab runners are taking jobs" ;;
  *)
    want=on
    why="the canary is '${status}${conclusion:+ / $conclusion}' after ${WAIT_SECONDS:-180}s: homelab runners are not taking jobs" ;;
esac

current="$("$GH" api "repos/${REPO}/actions/variables/${VAR}" --jq .value 2>/dev/null || echo missing)"
echo "queue-runner-watch: ${why}; ${VAR} is '${current}', want '${want}'"

if [ "$current" != "$want" ]; then
  if [ "$current" = missing ]; then
    "$GH" api -X POST "repos/${REPO}/actions/variables" -f name="$VAR" -f value="$want" >/dev/null
  else
    "$GH" api -X PATCH "repos/${REPO}/actions/variables/${VAR}" -f value="$want" >/dev/null
  fi
  if [ "$want" = on ]; then
    echo "::warning::queue jobs fall back to GitHub-hosted runners: ${why}"
  else
    echo "queue jobs return to the homelab runners"
  fi
fi

# A canary nobody picked up must not wait in the queue for a runner that may
# come back hours later.
if [ "$want" = on ] && [ "$status" != completed ] && [ "$status" != in_progress ]; then
  "$GH" api -X POST "repos/${REPO}/actions/runs/${RUN_ID}/cancel" >/dev/null || true
fi
