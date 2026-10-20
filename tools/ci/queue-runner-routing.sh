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

# queue-runner-routing — a workflow may name the homelab runner only through one
# exact rule, so a pull request can never choose it.
#
#   bash tools/ci/queue-runner-routing.sh .github/workflows
#
# The repository is public and allows fork pull requests, which run THEIR copy
# of every workflow (spec: docs/superpowers/specs/2026-10-19-queue-runners-on-
# homelab-design.md §5). So `runs-on` may reach the self-hosted label
# `vitruvian-queue` only through ROUTED below: merge queue or push to main, the
# QUEUE_RUNNER switch on, the fallback off, else GitHub-hosted. Any other
# non-comment mention of the label or of the QUEUE_RUNNER variables, in any
# workflow, fails. queue-runner-watch.yaml is the one exemption: it is its own
# canary and writes the fallback.
set -euo pipefail

DIR="${1:?usage: queue-runner-routing.sh <workflows-dir>}"
ROUTED="runs-on: \${{ (github.event_name == 'merge_group' || (github.event_name == 'push' && github.ref == 'refs/heads/main')) && vars.QUEUE_RUNNER == 'on' && vars.QUEUE_RUNNER_FALLBACK != 'on' && 'vitruvian-queue' || 'ubuntu-26.04' }}"

fail=0
for f in "$DIR"/*.yaml; do
  [ "$(basename "$f")" = queue-runner-watch.yaml ] && continue
  n=0
  while IFS= read -r line; do
    n=$((n + 1))
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in '#'*) continue ;; esac
    case "$line" in
      *vitruvian-queue* | *QUEUE_RUNNER*)
        # Same text, any indentation or "- " list marker, nothing else on the line.
        body="${trimmed#- }"
        if [ "$body" != "$ROUTED" ]; then
          echo "queue-runner-routing: $f:$n names the homelab runner outside the one allowed rule:" >&2
          echo "    $trimmed" >&2
          fail=1
        fi ;;
    esac
  done <"$f"
done

if [ "$fail" -ne 0 ]; then
  echo "queue-runner-routing: allowed: $ROUTED" >&2
  exit 1
fi
echo "queue-runner-routing: ok"
