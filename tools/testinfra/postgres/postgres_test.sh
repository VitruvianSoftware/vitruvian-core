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

# usage: postgres_test.sh <run-postgres> <check-postgres>
#
# Holds either implementation (the .sh scripts or the Rust binaries) to the
# same contract with stand-in initdb / postgres / pg_isready that record what
# they were given. No real database starts.
set -euo pipefail

RUN="$1"
CHECK="$2"
case "$RUN" in /*) ;; *) RUN="$PWD/$RUN" ;; esac
case "$CHECK" in /*) ;; *) CHECK="$PWD/$CHECK" ;; esac

ok() { echo "ok: $*"; }
fail() {
	echo "FAIL: $*" >&2
	exit 1
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat >"$T/bin/initdb" <<'STUB'
#!/bin/sh
echo "initdb $* LC_ALL=$LC_ALL LANG=$LANG" >>"$LOG"
echo "initdb chatter on stdout"
exit "${INITDB_RC:-0}"
STUB
cat >"$T/bin/postgres" <<'STUB'
#!/bin/sh
echo "postgres $* LC_ALL=$LC_ALL LANG=$LANG" >>"$LOG"
exit 7
STUB
cat >"$T/bin/pg_isready" <<'STUB'
#!/bin/sh
echo "pg_isready $*" >>"$LOG"
exit "${ISREADY_RC:-0}"
STUB
chmod +x "$T/bin/"*
export LOG="$T/log"

# A run: initdb (its stdout silenced), then postgres replaces the process, so
# its exit status is the run's.
: >"$LOG"
rc=0
out="$(LC_ALL=en_US.UTF-8 "$RUN" "$T/bin/initdb" "$T/bin/postgres" 5433 "$T/tmp" 2>/dev/null)" || rc=$?
[[ "$rc" -eq 7 ]] || fail "run: expected postgres's exit 7, got $rc: $out"
[[ -z "$out" ]] || fail "run: initdb's stdout leaked: $out"
want="initdb --pgdata=$T/tmp/pgdata --username=postgres --auth=trust --no-sync LC_ALL=C LANG=C
postgres -D $T/tmp/pgdata -p 5433 -c listen_addresses=127.0.0.1 -c unix_socket_directories= -c fsync=off -c synchronous_commit=off -c full_page_writes=off LC_ALL=C LANG=C"
[[ "$(cat "$LOG")" == "$want" ]] || fail "run: wrong calls:
$(cat "$LOG")"
ok "run: initdb then postgres, C locale, loopback TCP only"

# initdb failing stops the run with its status; postgres never starts.
: >"$LOG"
rc=0
INITDB_RC=3 "$RUN" "$T/bin/initdb" "$T/bin/postgres" 5433 "$T/tmp" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 3 ]] || fail "run: initdb failure should exit 3, got $rc"
grep -q '^postgres' "$LOG" && fail "run: postgres started after initdb failed"
ok "run: an initdb failure is the run's failure"

# Too few arguments.
rc=0
out="$("$RUN" a b c 2>&1)" || rc=$?
# shellcheck disable=SC2016 # bash's literal message names "$4"
[[ "$rc" -eq 1 && "$out" == *'$4: unbound variable' ]] || fail "run: missing tmpdir: rc=$rc $out"
ok "run: a missing argument is refused"

# check: pg_isready against loopback, its status passed through.
: >"$LOG"
rc=0
ISREADY_RC=2 "$CHECK" "$T/bin/pg_isready" 5433 || rc=$?
[[ "$rc" -eq 2 ]] || fail "check: expected pg_isready's exit 2, got $rc"
[[ "$(cat "$LOG")" == "pg_isready -h 127.0.0.1 -p 5433 -U postgres" ]] || fail "check: wrong call: $(cat "$LOG")"
ok "check: pg_isready on 127.0.0.1 as postgres, status passed through"

rc=0
out="$("$CHECK" "$T/bin/pg_isready" 2>&1)" || rc=$?
# shellcheck disable=SC2016 # bash's literal message names "$2"
[[ "$rc" -eq 1 && "$out" == *'$2: unbound variable' ]] || fail "check: missing port: rc=$rc $out"
ok "check: a missing port is refused"

echo "All postgres tests passed."
