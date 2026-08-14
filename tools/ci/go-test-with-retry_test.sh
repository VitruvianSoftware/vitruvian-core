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

# Unit tests for tools/ci/go-test-with-retry.sh. Exercises the pure
# is_transient_go_test_error classifier by SOURCING the script (same pattern
# as //tools/deploy:cloud-run_test.sh's resolve_smoke_url coverage) — no real
# `go test`, no network. This is exactly the logic the CI-workflow-hygiene
# audit flagged as most in need of coverage: it was previously inline YAML
# and untestable in place.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/go-test-with-retry.sh"

fails=0
ok() { echo "ok - $1"; }
bad() { echo "NOT OK - $1"; fails=$((fails + 1)); }

# shellcheck source=/dev/null
source "$SCRIPT"   # source-safe: main() runs only when executed, not sourced
# Sourcing imported go-test-with-retry.sh's `set -euo pipefail`; clear the
# inherited -e so a deliberately-failing classifier call below doesn't abort
# this test (same fix-up cloud-run_test.sh applies after its own `source`).
set +e -u -o pipefail

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

check_transient() { # <label> <want 0|1> <content>
  local label="$1" want="$2" content="$3" f="$work/case"
  printf '%s\n' "$content" > "$f"
  if is_transient_go_test_error "$f"; then got=0; else got=1; fi
  if [ "$got" = "$want" ]; then
    ok "$label"
  else
    bad "$label (got rc=$got, want rc=$want)"
  fi
}

echo "--- known transient network signatures (must retry, rc=0/match) ---"
check_transient "stream error" 0 'go: downloading github.com/foo v1.2.3
http2: stream error: stream ID 5; INTERNAL_ERROR'
check_transient "connection reset" 0 'read tcp 10.0.0.1:443: connection reset by peer'
check_transient "unexpected EOF" 0 'go: github.com/foo@v1.2.3: unexpected EOF'
check_transient "TLS handshake timeout" 0 'Get "https://proxy.golang.org/...": net/http: TLS handshake timeout'
check_transient "i/o timeout" 0 'dial tcp: i/o timeout'
check_transient "dial tcp timeout" 0 'dial tcp 142.250.0.1:443: i/o timeout'
check_transient "dial tcp refused" 0 'dial tcp 127.0.0.1:443: connect: connection refused'
check_transient "no such host" 0 'dial tcp: lookup proxy.golang.org: no such host'
check_transient "Client.Timeout" 0 'Get "https://proxy.golang.org/x": net/http: request canceled while waiting for connection (Client.Timeout exceeded while awaiting headers)'
check_transient "server misbehaving" 0 'lookup proxy.golang.org: server misbehaving'
check_transient "GOAWAY" 0 'http2: server sent GOAWAY and closed the connection'
check_transient "context deadline exceeded" 0 'context deadline exceeded'
check_transient "proxy.golang.org 5xx" 0 'go: github.com/foo@v1.2.3: reading https://proxy.golang.org/github.com/foo/@v/v1.2.3.info: 503 Service Unavailable'
check_transient "case-insensitive match" 0 'GOT A Connection Reset BY peer'

echo "--- real failures must NOT be classified as transient (rc=1/no-match) ---"
check_transient "assertion failure" 1 '--- FAIL: TestFoo (0.00s)
    foo_test.go:42: expected 1, got 2
FAIL'
check_transient "compile error" 1 './foo.go:10:2: undefined: bar'
check_transient "bare EOF" 1 'unexpected end of JSON input: EOF'
check_transient "panic" 1 'panic: runtime error: index out of range [3] with length 2'
check_transient "empty output" 1 ''

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails" >&2; exit 1; fi
echo "ALL PASS"
