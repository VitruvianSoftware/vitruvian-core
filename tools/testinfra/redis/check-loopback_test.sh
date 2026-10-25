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

# usage: check-loopback_test.sh <check-loopback>
#
# Holds either implementation (the script or the Rust binary) to the same
# contract against real sockets: python3 listens on a port, a stand-in for
# rules_itest's port helper names that port, and the check must pass only
# when 127.0.0.1 is the one address listening on it.
set -euo pipefail

CHECK="$1"
case "$CHECK" in /*) ;; *) CHECK="$PWD/$CHECK" ;; esac

ok() { echo "ok: $*"; }
fail() {
	echo "FAIL: $*" >&2
	exit 1
}

T="$(mktemp -d)"
LISTENER=""
cleanup() {
	if [[ -n "$LISTENER" ]]; then kill "$LISTENER" 2>/dev/null || true; fi
	rm -rf "$T"
}
trap cleanup EXIT

cat >"$T/port" <<'STUB'
#!/bin/sh
echo "$1" >"$PORT_LOG"
cat "$PORT_FILE"
STUB
chmod +x "$T/port"
export GET_ASSIGNED_PORT_BIN="$T/port" PORT_LOG="$T/port.log" PORT_FILE="$T/port.txt"
export ITEST_SERVICE_LABEL="@@//svc:redis"

# listen <address>: a listening socket on a free port, its number in port.txt.
listen() {
	stop
	rm -f "$PORT_FILE"
	python3 -c '
import socket, sys, time
s = socket.socket(socket.AF_INET)
s.bind((sys.argv[1], 0))
s.listen()
with open(sys.argv[2] + ".tmp", "w") as f:
    f.write("%d\n" % s.getsockname()[1])
import os
os.rename(sys.argv[2] + ".tmp", sys.argv[2])
time.sleep(120)
' "$1" "$PORT_FILE" &
	LISTENER=$!
	for _ in $(seq 100); do
		[[ -s "$PORT_FILE" ]] && return 0
		sleep 0.1
	done
	fail "the listener did not start"
}
stop() {
	if [[ -n "$LISTENER" ]]; then
		kill "$LISTENER" 2>/dev/null || true
		wait "$LISTENER" 2>/dev/null || true
		LISTENER=""
	fi
}

listen 127.0.0.1
port="$(cat "$PORT_FILE")"
out="$("$CHECK" 2>&1)" || fail "loopback only should pass: $out"
[[ "$out" == "ok: @@//svc:redis listens on 127.0.0.1:$port only" ]] || fail "unexpected: $out"
[[ "$(cat "$PORT_LOG")" == "@@//svc:redis" ]] || fail "the port helper was not asked about the label"
ok "a loopback-only listener passes"

listen 0.0.0.0
port="$(cat "$PORT_FILE")"
rc=0
out="$("$CHECK" 2>&1)" || rc=$?
[[ "$rc" -eq 1 ]] || fail "a wildcard listener should fail, rc=$rc: $out"
[[ "$out" == *"must listen on 127.0.0.1:$port only; sockets LISTENing on port $port:"* ]] || fail "unexpected: $out"
ok "a wildcard listener fails and is listed"

stop
rc=0
out="$("$CHECK" 2>&1)" || rc=$?
[[ "$rc" -ne 0 ]] || fail "nothing listening should fail: $out"
ok "nothing listening fails"

rc=0
out="$(env -u ITEST_SERVICE_LABEL "$CHECK" 2>&1)" || rc=$?
[[ "$rc" -eq 1 && "$out" == *"ITEST_SERVICE_LABEL: set to the itest service label to check" ]] || fail "no label: rc=$rc $out"
ok "no service label is refused"

: >"$PORT_FILE"
rc=0
out="$("$CHECK" 2>&1)" || rc=$?
[[ "$rc" -eq 1 && "$out" == "no assigned port for @@//svc:redis in ASSIGNED_PORTS" ]] || fail "no port: rc=$rc $out"
ok "no assigned port is refused"

echo "All check-loopback tests passed."
