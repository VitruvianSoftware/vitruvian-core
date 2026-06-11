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

# usage: run-postgres.sh <initdb> <postgres> <port> <tmpdir>
set -euo pipefail
INITDB="$1"
POSTGRES="$2"
PORT="$3"
TMP="$4"

# macOS: anything that goes multithreaded before fork (locale lookups) crashes
# the postmaster with "postmaster became multithreaded during startup".
export LC_ALL=C LANG=C

DATADIR="$TMP/pgdata"
"$INITDB" --pgdata="$DATADIR" --username=postgres --auth=trust --no-sync >/dev/null

# TCP-only on loopback: TEST_TMPDIR routinely exceeds the unix-socket path
# limit. Durability knobs are off: the database is disposable per test.
exec "$POSTGRES" \
  -D "$DATADIR" \
  -p "$PORT" \
  -c listen_addresses=127.0.0.1 \
  -c unix_socket_directories= \
  -c fsync=off \
  -c synchronous_commit=off \
  -c full_page_writes=off
