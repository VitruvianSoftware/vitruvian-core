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

# queue-runner-routing_test — the real workflows pass, and every way a workflow
# could hand the homelab runner to a pull request fails.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${1:-$HERE/queue-runner-routing.sh}"
# Bazel passes every workflow's path, space-separated: the directory is the first one's.
REAL=""
[ -n "${2:-}" ] && REAL="$(dirname "${2%% *}")"
failures=0
ok() { echo "  ok: $1"; }
bad() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

ROUTED="runs-on: \${{ (github.event_name == 'merge_group' || (github.event_name == 'push' && github.ref == 'refs/heads/main')) && vars.QUEUE_RUNNER == 'on' && vars.QUEUE_RUNNER_FALLBACK != 'on' && 'vitruvian-queue' || 'ubuntu-26.04' }}"

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

# case <name> <expect: pass|fail> <workflow text> -> checks the script's verdict
case_() {
  rm -rf "$W/d"; mkdir "$W/d"; printf '%s\n' "$3" >"$W/d/x.yaml"
  if [[ "$SCRIPT" == *.sh ]]; then
    bash "$SCRIPT" "$W/d" >"$W/out" 2>&1 && got=pass || got=fail
  else
    "$SCRIPT" "$W/d" >"$W/out" 2>&1 && got=pass || got=fail
  fi
  [ "$got" = "$2" ] && ok "$1" || bad "$1: expected $2, got $got: $(cat "$W/out")"
}

echo "== allowed =="
case_ "a plain hosted job" pass "jobs:
  a:
    runs-on: ubuntu-26.04"
case_ "the one routing rule" pass "jobs:
  a:
    $ROUTED"
case_ "the rule inside a list item" pass "jobs:
  - $ROUTED"
case_ "a comment may name it" pass "# routed to vitruvian-queue when QUEUE_RUNNER is on
jobs:
  a:
    runs-on: ubuntu-26.04"

echo "== refused =="
case_ "naming the runner directly" fail "jobs:
  a:
    runs-on: vitruvian-queue"
case_ "routing without the event guard (a pull request could pick it)" fail "jobs:
  a:
    runs-on: \${{ vars.QUEUE_RUNNER == 'on' && 'vitruvian-queue' || 'ubuntu-26.04' }}"
case_ "the guard with pull_request allowed" fail "jobs:
  a:
    runs-on: \${{ (github.event_name == 'merge_group' || github.event_name == 'pull_request') && vars.QUEUE_RUNNER == 'on' && vars.QUEUE_RUNNER_FALLBACK != 'on' && 'vitruvian-queue' || 'ubuntu-26.04' }}"
case_ "the rule without the fallback check" fail "jobs:
  a:
    runs-on: \${{ (github.event_name == 'merge_group' || (github.event_name == 'push' && github.ref == 'refs/heads/main')) && vars.QUEUE_RUNNER == 'on' && 'vitruvian-queue' || 'ubuntu-26.04' }}"
case_ "the label in a matrix" fail "jobs:
  a:
    strategy:
      matrix:
        os: [vitruvian-queue]
    runs-on: \${{ matrix.os }}"
case_ "the switch used in an if" fail "jobs:
  a:
    if: vars.QUEUE_RUNNER == 'on'
    runs-on: ubuntu-26.04"

echo "== the exemption =="
rm -rf "$W/d"; mkdir "$W/d"
printf 'jobs:\n  canary:\n    runs-on: vitruvian-queue\n' >"$W/d/queue-runner-watch.yaml"
if [[ "$SCRIPT" == *.sh ]]; then
  bash "$SCRIPT" "$W/d" >/dev/null 2>&1 && ok "queue-runner-watch.yaml may name the runner" || bad "the watcher was refused"
else
  "$SCRIPT" "$W/d" >/dev/null 2>&1 && ok "queue-runner-watch.yaml may name the runner" || bad "the watcher was refused"
fi
cp "$W/d/queue-runner-watch.yaml" "$W/d/other.yaml"
if [[ "$SCRIPT" == *.sh ]]; then
  bash "$SCRIPT" "$W/d" >/dev/null 2>&1 && bad "a copy under another name was allowed" || ok "the same text under another name is refused"
else
  "$SCRIPT" "$W/d" >/dev/null 2>&1 && bad "a copy under another name was allowed" || ok "the same text under another name is refused"
fi

if [ -n "$REAL" ]; then
  echo "== the real workflows =="
  if [[ "$SCRIPT" == *.sh ]]; then
    bash "$SCRIPT" "$REAL" >"$W/out" 2>&1 && ok "every workflow in the repo passes" || bad "the repo's workflows: $(cat "$W/out")"
  else
    "$SCRIPT" "$REAL" >"$W/out" 2>&1 && ok "every workflow in the repo passes" || bad "the repo's workflows: $(cat "$W/out")"
  fi
fi

[ "$failures" -eq 0 ] || { echo "queue-runner-routing_test: $failures failure(s)" >&2; exit 1; }
echo "queue-runner-routing_test: all checks passed"
