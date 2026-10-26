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

# queue-runner-watch_test — each decision the watcher makes, with a fake gh that
# answers the canary's state and the variable's value and logs every call.
set -uo pipefail

SCRIPT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/queue-runner-watch.sh}"
failures=0
ok() { echo "  ok: $1"; }
bad() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
cat >"$W/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_DIR/calls"
case "$*" in
  *"/jobs"*) if [ "${FAKE_NOJOB:-}" = 1 ]; then :; else echo "$FAKE_CANARY"; fi ;;
  # The real gh prints the API's error body on STDOUT for a 404, then exits 1.
  *"/variables/QUEUE_RUNNER_FALLBACK"*"--jq"*)
    if [ "$FAKE_VAR" = missing ]; then
      echo '{"message":"Not Found","documentation_url":"https://docs.github.com/rest/actions/variables#get-a-repository-variable","status":"404"}'
      exit 1
    fi
    echo "$FAKE_VAR" ;;
esac
STUB
chmod +x "$W/gh"

# run <canary state> <variable value> -> out/rc; calls in $W/calls
run() {
  rm -f "$W/calls"; : >"$W/calls"
  if [[ "$SCRIPT" == *.sh ]]; then
    out="$(FAKE_DIR="$W" FAKE_CANARY="$1" FAKE_VAR="$2" FAKE_NOJOB="${3:-}" GH_BIN="$W/gh" REPO=o/r RUN_ID=7 WAIT_SECONDS=0 bash "$SCRIPT" 2>&1)"; rc=$?
  else
    out="$(FAKE_DIR="$W" FAKE_CANARY="$1" FAKE_VAR="$2" FAKE_NOJOB="${3:-}" GH_BIN="$W/gh" REPO=o/r RUN_ID=7 WAIT_SECONDS=0 "$SCRIPT" 2>&1)"; rc=$?
  fi
}
wrote() { grep -q -- "$1" "$W/calls"; }
no_write() { ! grep -q -E -- '-X (PATCH|POST) repos/o/r/actions/variables' "$W/calls"; }

echo "== healthy canary =="
run "in_progress " on
[ $rc = 0 ] && wrote "-X PATCH repos/o/r/actions/variables/QUEUE_RUNNER_FALLBACK -f value=off" &&
  ok "a canary that is running clears the fallback" || bad "in_progress/on: rc=$rc $(cat "$W/calls")"
run "completed success" on
wrote "-f value=off" && ok "a canary that finished clears the fallback" || bad "completed success: $(cat "$W/calls")"
run "in_progress " off
[ $rc = 0 ] && no_write && ok "already off: nothing is written" || bad "in_progress/off wrote: $(cat "$W/calls")"

echo "== unhealthy canary =="
run "queued " off
[ $rc = 0 ] && wrote "-X PATCH repos/o/r/actions/variables/QUEUE_RUNNER_FALLBACK -f value=on" &&
  wrote "-X POST repos/o/r/actions/runs/7/cancel" && grep -q "::warning::" <<<"$out" &&
  ok "a canary nobody took sets the fallback, warns, and is cancelled" || bad "queued/off: rc=$rc $(cat "$W/calls") $out"
run "completed failure" off
wrote "-f value=on" && ! wrote "/cancel" && ok "a canary that failed sets the fallback (nothing to cancel)" || bad "completed failure: $(cat "$W/calls")"
run "waiting " off
wrote "-f value=on" && ok "a canary waiting for approval or capacity sets the fallback" || bad "waiting: $(cat "$W/calls")"
run "queued " on
[ $rc = 0 ] && no_write && wrote "/cancel" && ok "already on: not rewritten, the stuck canary is still cancelled" || bad "queued/on: $(cat "$W/calls")"

echo "== first run: the variable does not exist yet =="
run "queued " missing
wrote "-X POST repos/o/r/actions/variables -f name=QUEUE_RUNNER_FALLBACK -f value=on" && ok "created when missing" || bad "missing: $(cat "$W/calls")"
run "in_progress " missing
wrote "-X POST repos/o/r/actions/variables -f name=QUEUE_RUNNER_FALLBACK -f value=off" && ok "created as off when the canary runs" || bad "missing/healthy: $(cat "$W/calls")"

echo "== cannot decide =="
run "" on 1
if [ $rc -ne 0 ] && no_write; then ok "no canary job in the run: fails and changes nothing"; else bad "nojob: rc=$rc $(cat "$W/calls")"; fi

[ "$failures" -eq 0 ] || { echo "queue-runner-watch_test: $failures failure(s)" >&2; exit 1; }
echo "queue-runner-watch_test: all checks passed"
