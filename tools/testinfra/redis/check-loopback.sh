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

# usage: ITEST_SERVICE_LABEL=<label> check-loopback.sh
#
# Runs as the `test` of a rules_itest service_test once the named service is
# healthy. Fails unless every socket LISTENing on the service's assigned port
# is bound to 127.0.0.1.
#
# Why: svcinit reserves each autoassigned port by binding 127.0.0.1:0, so that
# is the only address it knows is free. A service that binds the wildcard
# ("*" and "::*", redis-server's default) also competes with every other
# socket on that port, on any address. Ports come from the ephemeral range,
# so an unrelated outbound connection can hold the same port on another
# address, the bind fails with "Address already in use", and the whole
# service_test dies in setup (merge-queue run 38383931089, 2026-10-13).
set -euo pipefail

label="${ITEST_SERVICE_LABEL:?set to the itest service label to check}"
port="$("${GET_ASSIGNED_PORT_BIN:?not running under rules_itest svcinit}" "$label")"
if [ -z "$port" ]; then
	echo "no assigned port for $label in ASSIGNED_PORTS" >&2
	exit 1
fi

if [ -r /proc/net/tcp ]; then
	# Linux. Rows are "sl local_address rem_address st ..."; local_address is
	# HEXIP:HEXPORT (0100007F is 127.0.0.1, 00000000 the wildcard) and st 0A
	# is LISTEN. tcp6 is absent when the kernel has IPv6 off.
	hex="$(printf '%04X' "$port")"
	listeners="$(
		{
			cat /proc/net/tcp
			cat /proc/net/tcp6 2> /dev/null || true
		} | awk -v p=":$hex" \
			'substr($2, length($2) - length(p) + 1) == p && $4 == "0A" { print $2 }' |
			sort -u
	)"
	want="0100007F:$hex"
elif [ -x /usr/sbin/lsof ]; then
	# macOS. The NAME column is "addr:port", followed by "(LISTEN)".
	listeners="$(
		/usr/sbin/lsof -nP -iTCP:"$port" -sTCP:LISTEN |
			awk 'NR > 1 { print $(NF - 1) }' |
			sort -u
	)"
	want="127.0.0.1:$port"
else
	echo "cannot inspect listening sockets here: no /proc/net/tcp and no /usr/sbin/lsof" >&2
	exit 1
fi

if [ "$listeners" != "$want" ]; then
	echo "$label must listen on 127.0.0.1:$port only; sockets LISTENing on port $port:" >&2
	echo "${listeners:-  (none)}" | sed 's/^/  /' >&2
	exit 1
fi
echo "ok: $label listens on 127.0.0.1:$port only"
