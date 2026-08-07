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
# go-test-infra_test.sh — regression guard for tools/ci/go-test-infra.sh.
#
# go-test-infra is a REQUIRED merge-queue check, and the script runs its 30
# modules through a concurrent pool. The expensive failure mode for that shape
# is not a crash — it is a green verdict the run did not earn: a pool that
# collects a child's output but drops its exit status reports "ok" while the
# tests are red, and nothing downstream can tell the difference. So the failure
# properties are asserted on the SCRIPT'S EXIT CODE and on the named modules in
# its summary, not merely on the transcript containing the word FAILED.
#
# The three properties that specifically pay for the parallelism:
#
#   * a failure in ANY module fails the check — including one that is not the
#     first to run and not the first to finish (the swallowed-status bug);
#   * every module still runs when an earlier one fails — the inline loop this
#     replaced ran under `set -e` and stopped at the first, so a bump that broke
#     five modules reported one;
#   * the transcript is in module order no matter which module finishes first —
#     otherwise the log is unbisectable and the run is unreproducible.
#
# `go` is stubbed. This pins the runner's decision logic, not the Go toolchain:
# a real toolchain would make the suite depend on the network, the platform, and
# a multi-GB module cache to assert control flow it does not exercise.
#
# Run: bash tools/ci/go-test-infra_test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNDER_TEST="${SCRIPT_DIR}/go-test-infra.sh"
[ -f "${UNDER_TEST}" ] || { echo "FATAL: ${UNDER_TEST} not found" >&2; exit 1; }

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  PASS: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

check_eq() { # desc expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi
}
check_contains() { # desc needle haystack
  case "$3" in *"$2"*) ok "$1" ;; *) bad "$1 (missing '$2')" ;; esac
}
check_not_contains() { # desc needle haystack
  case "$3" in *"$2"*) bad "$1 (unexpectedly found '$2')" ;; *) ok "$1" ;; esac
}

# ---------------------------------------------------------------------------
# Fixture: a throwaway tree of fake Go modules plus a stub `go` on PATH.
#
# The stub's behaviour is driven by files in the fixture so a single stub covers
# both the pass and fail cases: a module containing FAIL_MARKER exits 1, and one
# containing SLOW_MARKER sleeps first. The sleep is what makes the ordering
# assertions meaningful — without it, modules finish in launch order and an
# implementation that simply streamed output would pass by luck.
# ---------------------------------------------------------------------------
FIXTURE="$(mktemp -d)"
trap 'rm -rf "${FIXTURE}"' EXIT

mkdir -p "${FIXTURE}/bin"
cat >"${FIXTURE}/bin/go" <<'STUB'
#!/usr/bin/env bash
# Stub `go`. Invoked as `go test ./...` from inside a module directory.
[ -f ./SLOW_MARKER ] && sleep 1
if [ -f ./FAIL_MARKER ]; then
  echo "--- FAIL: TestStub (0.00s)"
  echo "FAIL	$(basename "$PWD")	0.001s"
  exit 1
fi
echo "ok  	$(basename "$PWD")	0.001s"
exit 0
STUB
chmod +x "${FIXTURE}/bin/go"
export PATH="${FIXTURE}/bin:${PATH}"

# mod <name> [tested|untested] [fail] [slow]
mod() {
  d="${FIXTURE}/iac/$1"
  mkdir -p "$d"
  echo "module $1" >"$d/go.mod"
  [ "${2:-tested}" = "tested" ] && echo "package p" >"$d/p_test.go"
  case " ${3:-} ${4:-} " in *" fail "*) : >"$d/FAIL_MARKER" ;; esac
  case " ${3:-} ${4:-} " in *" slow "*) : >"$d/SLOW_MARKER" ;; esac
}

# `env`, not a bare `VAR=x "$@"`: a quoted expansion is parsed as the command
# name, never as an assignment, so the bare form silently exits 127 instead of
# running anything -- which would have made every assertion below vacuous.
run_under_test() { (cd "${FIXTURE}" && env GO_TEST_INFRA_ROOTS="iac" "$@" bash "${UNDER_TEST}" 2>&1); }

# ---------------------------------------------------------------------------
echo "== all modules green =="
mod a-first tested "" slow      # slowest, launched first
mod b-plain tested
mod c-last  tested
mod d-notests untested          # no *_test.go -> must be skipped
mkdir -p "${FIXTURE}/iac/vendored/vendor/dep" && echo "module dep" >"${FIXTURE}/iac/vendored/vendor/dep/go.mod"

out="$(run_under_test GO_TEST_INFRA_JOBS=4)"; rc=$?
check_eq        "green run exits 0" 0 "$rc"
check_contains  "reports the module count" "ran go test in 3 IaC module(s)" "$out"
check_not_contains "skips modules with no *_test.go" "d-notests" "$out"
check_not_contains "skips vendored go.mod" "vendor/dep" "$out"

# Module order, not completion order: a-first sleeps, so a streaming
# implementation would emit c-last before it.
order="$(printf '%s\n' "$out" | sed -n 's/^::group::go test iac\/\([a-z-]*\) .*/\1/p' | tr '\n' ' ')"
check_eq "transcript is in module order despite finish order" "a-first b-plain c-last " "$order"

# ---------------------------------------------------------------------------
echo "== a failure anywhere fails the check =="
rm -rf "${FIXTURE}/iac"
mod a-slow-green tested "" slow  # launched first, finishes LAST
mod b-green tested
mod c-red   tested fail          # launched last, finishes FIRST

out="$(run_under_test GO_TEST_INFRA_JOBS=4)"; rc=$?
check_eq       "one red module fails the whole check" 1 "$rc"
check_contains "names the failing module in the summary" "- iac/c-red" "$out"
check_contains "counts the failures" "FAILED in 1 of 3 IaC module(s)" "$out"
check_contains "still runs the modules launched before it" "ok  	a-slow-green" "$out"
check_contains "still runs the modules launched after it"  "ok  	b-green" "$out"

# The swallowed-status bug: the red module is the FIRST to finish while two
# others are still running, so its status has to survive the pool's teardown.
check_contains "marks the red module FAILED in its group header" "go test iac/c-red (FAILED)" "$out"

# ---------------------------------------------------------------------------
echo "== every failure is reported, not just the first =="
rm -rf "${FIXTURE}/iac"
mod a-red tested fail
mod b-red tested fail
mod c-green tested

out="$(run_under_test GO_TEST_INFRA_JOBS=4)"; rc=$?
check_eq       "multiple red modules still exit 1" 1 "$rc"
check_contains "reports every failure, not just the first" "FAILED in 2 of 3 IaC module(s)" "$out"
check_contains "names the first failure"  "- iac/a-red" "$out"
check_contains "names the second failure" "- iac/b-red" "$out"
check_contains "does not stop at the first failure" "ok  	c-green" "$out"

# ---------------------------------------------------------------------------
echo "== serial execution keeps the same verdict =="
# JOBS=1 is the pre-parallel behaviour; it must agree with the pool, or the
# concurrency is deciding the verdict.
out="$(run_under_test GO_TEST_INFRA_JOBS=1)"; rc=$?
check_eq       "serial run reaches the same verdict" 1 "$rc"
check_contains "serial run reports the same failure count" "FAILED in 2 of 3 IaC module(s)" "$out"

# ---------------------------------------------------------------------------
echo "== no modules is not silently green =="
rm -rf "${FIXTURE}/iac"
mod only-untested untested

out="$(run_under_test GO_TEST_INFRA_JOBS=4)"; rc=$?
check_eq       "a tree with no tested modules exits 0" 0 "$rc"
check_contains "says so out loud rather than looking like a full run" \
               "ran go test in 0 IaC module(s)" "$out"

# ---------------------------------------------------------------------------
echo
echo "go-test-infra_test: ${PASS} passed, ${FAIL} failed"
[ "${FAIL}" -eq 0 ] || exit 1
