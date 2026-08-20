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

# transient-lib.sh — shared classifier for "the Go module proxy / network
# failed", as distinct from "your code is wrong".
#
# WHY SHARED. This signature reaches every tool that shells a `go` command, and
# a tool that cannot tell the two apart MISREPORTS. Observed on 2026-08-20:
# proxy.golang.org returned `INTERNAL_ERROR` mid-run and
# `tools/gomod/tidy.sh --check` announced
#
#   ✗ gomod — 2 of 58 module(s) are out of sync with their `replace` targets
#      Fix with: bazel run //tools/gomod:tidy
#
# Nothing was out of sync: the same commit re-ran clean at "all 58 module(s)
# tidy". The gate told a developer to fix a problem that did not exist, because
# `go mod tidy -diff` exits non-zero for BOTH drift and network failure and the
# caller collapsed the two.
#
# `tools/ci/go-test-with-retry.sh` already carried this classifier and handled
# the same blip correctly. Keeping one copy is the point: a second, drifting
# regex is how one lane silently stops recognising what the other still does.
#
# NOT a general "did anything fail" test. It matches TRANSPORT failures only,
# so a genuine `go` error -- a real diff, a compile failure, a missing module --
# never matches and is never retried or excused.

# is_transient_network_error <output-file> — true when captured `go` output
# carries a recognizable module-proxy/network transport failure.
is_transient_network_error() {
    local out_file="$1"
    # grep reads out_file directly, not a pipe: `grep -q` exits the instant it
    # matches, and piping a live writer into it risks SIGPIPE-ing that writer --
    # which, under pipefail, would make this read FALSE even on a real match
    # (verified: 200KB of matching output through `printf | grep -q` reports
    # exit 141, not the match). A file has no writer left to signal.
    grep -qiE \
        'stream error|connection reset|unexpected EOF|TLS handshake timeout|i/o timeout|dial tcp.*(timeout|refused)|no such host|Client\.Timeout exceeded while awaiting headers|server misbehaving|GOAWAY|context deadline exceeded|proxy\.golang\.org.*\b5[0-9]{2}\b' \
        "$out_file"
}
