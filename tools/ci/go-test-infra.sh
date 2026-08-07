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
#
# go-test-infra.sh — run `go test ./...` across the IaC Go modules.
#
# These modules (infrastructure/pulumi/** and <app>/infra/**) are deliberately
# NOT go.work members and `pulumi_project` emits only `bazel run` wrappers, so
# neither the go-test matrix nor `bazel test //...` ever sees them. This script
# is the `go-test-infra` required check's body; it was inline in ci.yaml until
# the loop became CI's critical path (see WHY PARALLEL below).
#
# Modules are DISCOVERED, not listed, so a new app's infra is covered the day it
# lands. Only modules that actually contain a *_test.go run: `go test ./...` in
# a module with none is a slow no-op that still resolves the whole graph.
#
# WHY PARALLEL (2026-08-07). Measured on the postsubmit lane: 30 modules, 692s
# of wall-clock to execute ~0.7s of actual tests. Effectively all of it is Go
# compilation — each module is its own module graph, so the first few distinct
# dependency sets each pay a full cold compile (gcp-bootstrap alone 139s) and
# the rest ride the intra-run GOCACHE at 3-5s. The obvious fix — persist GOCACHE
# across runs — is not available: a shared cache over all 30 modules measures
# 9.2GB against GitHub's 10GB repo-wide cache budget, which would evict the
# llvm-contents and setup-bazel entries that ci.yaml's other lanes depend on
# (tracked separately). Running the modules concurrently needs no cache budget
# at all. Measured cold at GOMAXPROCS=4 (the runner's core count): serial 225s,
# -P2 155s, -P4 151s — so ~-33%, with the gain flattening past 2 because a
# single module's compile already saturates the cores.
#
# WHY NOT `set -e` ON THE POOL. The inline loop ran under `set -euo pipefail`,
# so the FIRST failing module aborted the run and the later ones never reported.
# That is worse than it looks on a 30-module gate: a dependency bump that breaks
# five modules showed one. This runs every module and fails at the end with the
# full list. The property that must never regress is that a failure ANYWHERE
# still fails the check — asserted in go-test-infra_test.sh, because a parallel
# pool that swallows a child's exit status is exactly the bug that turns a
# required gate green while the tests are red.
#
# Usage: tools/ci/go-test-infra.sh
#   GO_TEST_INFRA_JOBS   concurrency (default: min(nproc, 4))
#   GO_TEST_INFRA_ROOTS  space-separated discovery roots (default: the two above)

set -uo pipefail

# ---------------------------------------------------------------------------
# Worker mode: re-exec of this same script for ONE module, run by the xargs
# pool below. Output is buffered to a file rather than written to stdout so
# concurrent modules cannot interleave their lines; the parent replays the logs
# in module order afterwards, keeping the transcript deterministic regardless of
# which module happens to finish first.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--run-one" ]; then
  dir="${2:?--run-one needs a module dir}"
  : "${GO_TEST_INFRA_WORKDIR:?--run-one needs GO_TEST_INFRA_WORKDIR}"
  slug="$(printf '%s' "$dir" | tr '/' '_')"

  if out="$(cd "$dir" && go test ./... 2>&1)"; then
    status="ok"
  else
    status="FAILED"
    # A marker file per failure, not an append to one shared file: concurrent
    # appends from the pool are only atomic below PIPE_BUF, and this gate's
    # verdict must not depend on that.
    : >"${GO_TEST_INFRA_WORKDIR}/${slug}.failed"
  fi

  {
    printf '::group::go test %s (%s)\n' "$dir" "$status"
    printf '%s\n' "$out"
    printf '::endgroup::\n'
  } >"${GO_TEST_INFRA_WORKDIR}/${slug}.log"
  exit 0
fi

# ---------------------------------------------------------------------------
# Parent mode.
# ---------------------------------------------------------------------------
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# These modules are deliberately not workspace members; resolving them through
# go.work would pick up the wrong module graph entirely.
export GOWORK=off

ROOTS="${GO_TEST_INFRA_ROOTS:-infrastructure/pulumi */infra}"

if [ -n "${GO_TEST_INFRA_JOBS:-}" ]; then
  JOBS="${GO_TEST_INFRA_JOBS}"
else
  ncpu="$( (command -v nproc >/dev/null 2>&1 && nproc) || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
  # Capped at 4: measured gain flattens past 2 (151s at -P4 vs 155s at -P2),
  # while every extra concurrent `go build` adds peak disk and RSS on a runner
  # that already carries a multi-GB GOCACHE by the end of the run.
  JOBS=$((ncpu > 4 ? 4 : ncpu))
fi
[ "${JOBS}" -ge 1 ] 2>/dev/null || JOBS=1

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT
export GO_TEST_INFRA_WORKDIR="${WORKDIR}"

# Discovery. Sorted so the transcript (and any bisect against it) is stable.
# shellcheck disable=SC2086 # ROOTS is a deliberate word-split list of roots.
mods="$(
  find ${ROOTS} -name go.mod -not -path '*/vendor/*' 2>/dev/null | sort | while IFS= read -r mod; do
    dir="$(dirname "$mod")"
    if find "$dir" -name '*_test.go' -print -quit 2>/dev/null | grep -q .; then
      printf '%s\n' "$dir"
    fi
  done
)"

if [ -z "${mods}" ]; then
  # Not an error: a repo state with no IaC tests is legitimate. It IS worth
  # saying out loud, because "0 modules" and "30 green modules" otherwise look
  # identical in a green check.
  echo "ran go test in 0 IaC module(s)"
  exit 0
fi

count="$(printf '%s\n' "${mods}" | wc -l | tr -d ' ')"
echo "Running go test across ${count} IaC module(s) with ${JOBS} job(s)..."

printf '%s\n' "${mods}" | xargs -P "${JOBS}" -I{} "${SELF}" --run-one {}

# Replay in module order, then verdict.
failed=""
while IFS= read -r dir; do
  slug="$(printf '%s' "$dir" | tr '/' '_')"
  [ -f "${WORKDIR}/${slug}.log" ] && cat "${WORKDIR}/${slug}.log"
  if [ -f "${WORKDIR}/${slug}.failed" ]; then
    failed="${failed}${dir}"$'\n'
  fi
done <<EOF
${mods}
EOF

echo "ran go test in ${count} IaC module(s)"

if [ -n "${failed}" ]; then
  nfailed="$(printf '%s' "${failed}" | grep -c . || true)"
  echo
  echo "FAILED in ${nfailed} of ${count} IaC module(s):"
  printf '%s' "${failed}" | sed 's/^/  - /'
  exit 1
fi
