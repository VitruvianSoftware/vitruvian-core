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

# go-test-with-retry.sh — `go test ./...` over every IaC Go module that
# actually carries tests, retrying a module ONLY on a recognizable transient
# module-proxy/network signature.
#
# A real compile or test failure is deterministic and would just fail
# identically on every attempt, so the retry never masks an actual bug. It
# exists for the residual case the setup-go module-download cache doesn't
# cover: a first run, a go.sum bump, or an evicted cache entry still hits the
# network raw. (Observed failure motivating this: a mid-download HTTP/2
# "stream error" fetching pulumi-kubernetes/sdk/v4, unrelated to the PR that
# hit it.) Not matching bare "EOF": io.EOF is routine in plenty of legitimate,
# non-network Go test failures, and matching it risks retrying (and thereby
# delaying the report of) a real bug instead of a flake.
#
# Exit: the exit status of the last module that failed after exhausting
# retries, or 0 if every module with tests passed. (main() sums nothing —
# each module's failure is reported inline via ::group::/::endgroup::, same
# as the original inline step; the step's own overall pass/fail is `set -e`
# propagating the first go_test_with_retry failure.)

set -euo pipefail

# is_transient_go_test_error <output-file> — pure classifier over captured
# `go test` output. Exported as its own function (rather than inlined in the
# retry loop) so it can be unit-tested directly by sourcing this script and
# calling it against fake fixture files, with no real `go test` invocation.
is_transient_go_test_error() {
  local out_file="$1"
  # grep reads out_file directly, not a pipe: `grep -q` exits the instant it
  # matches, and piping a live writer into it risks SIGPIPE-ing that writer --
  # which, under pipefail, would make this test read false even on a real
  # match (verified: 200KB of matching output through `printf | grep -q`
  # reports exit 141, not the match). A file has no writer left to signal.
  grep -qiE \
    'stream error|connection reset|unexpected EOF|TLS handshake timeout|i/o timeout|dial tcp.*(timeout|refused)|no such host|Client\.Timeout exceeded while awaiting headers|server misbehaving|GOAWAY|context deadline exceeded|proxy\.golang\.org.*\b5[0-9]{2}\b' \
    "$out_file"
}

go_test_with_retry() {
  local dir="$1" attempt status out_file
  out_file="$(mktemp)"
  for attempt in 1 2 3; do
    # `tee`, not `$(...)` capture: this pipeline's stdout goes straight
    # through to the job's own stdout AS IT HAPPENS (a module that HANGS
    # still leaves output behind if the job's timeout-minutes kills it),
    # while the same bytes land in out_file for the retry-pattern check
    # below. An earlier version buffered everything into a variable and only
    # printed it on return, which lost a hung module's output entirely -- and
    # a version after that tried `tee /dev/stderr` inside the substitution
    # instead, which is worse: reopening /dev/stderr fresh on every retry
    # attempt does not reliably continue appending to the redirected file, it
    # can silently overwrite -- verified losing two full attempts' worth of
    # output to exactly that before switching to a real file here.
    if (cd "$dir" && go test ./...) 2>&1 | tee "$out_file"; then
      rm -f "$out_file"
      return 0
    fi
    # PIPESTATUS[0], not `$?`: this line is a two-stage pipeline (go test |
    # tee), so `$?` right after it is tee's status (which is ~never
    # non-zero), not go test's. PIPESTATUS[0] is the first stage's real exit
    # code, unaffected by pipefail.
    status=${PIPESTATUS[0]}
    if [ "$attempt" -lt 3 ] && is_transient_go_test_error "$out_file"; then
      echo "::warning::go test in ${dir} hit a transient network error (attempt ${attempt}/3) -- retrying in $((attempt * 10))s" >&2
      sleep $((attempt * 10))
      continue
    fi
    rm -f "$out_file"
    return "$status"
  done
  rm -f "$out_file"
  return "$status"
}

main() {
  local mod dir ran=0
  while IFS= read -r mod; do
    dir="$(dirname "$mod")"
    # Only modules that actually carry tests: `go test ./...` in a module
    # with none is a slow no-op that still resolves the graph.
    if ! find "$dir" -name '*_test.go' -print -quit | grep -q .; then
      continue
    fi
    ran=$((ran + 1))
    echo "::group::go test $dir"
    go_test_with_retry "$dir"
    echo "::endgroup::"
  # */infra is a shell glob (not a variable), expanded by bash into every
  # app's infra/ dir as separate `find` start paths (tabula/infra,
  # oauth-user-inspector/infra, ...) before find ever runs -- find itself
  # does no globbing. Same literal pattern as the original inline step.
  done < <(find infrastructure/pulumi */infra -name go.mod -not -path '*/vendor/*' 2>/dev/null | sort)
  echo "ran go test in $ran IaC module(s)"
}

# Run main only when EXECUTED; stay quiet when SOURCED (so tests can exercise
# the pure is_transient_go_test_error classifier without running go test).
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  main "$@"
fi
