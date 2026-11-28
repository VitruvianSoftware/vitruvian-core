#!/bin/bash
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

# Tests the notary-submit part of sign-and-notarize.sh with a fake notarytool:
# a hang is stopped within its time and retried, a submission that already has
# an id is waited on rather than sent twice, a verdict is final, attempts and
# the run's budget are bounded, and nothing is left running.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Under Bazel the script sits beside this test in the runfiles.
script="${here}/sign-and-notarize.sh"
[ -f "${script}" ] || script="${TEST_SRCDIR:-}/_main/apps/desktop/vitruvian-code/scripts/sign-and-notarize.sh"

work="$(mktemp -d "${TEST_TMPDIR:-/tmp}/notary-test.XXXXXX")"
trap 'rm -rf "${work}"' EXIT

export NOTARY_ATTEMPT_SECONDS=2 NOTARY_ATTEMPTS=3 NOTARY_RETRY_PAUSE=0 NOTARY_HEARTBEAT_SECONDS=1
# Only the functions between the markers: the rest of the script runs.
sed -n '/^# >>> notary-submit$/,/^# <<< notary-submit$/p' "${script}" >"${work}/notary-submit.sh"
grep -q '^notary_submit()' "${work}/notary-submit.sh" || {
	echo "FAIL no notary-submit block in ${script}"
	exit 1
}

# The fake reads a script of behaviours, one line per call: hang, hangid (an
# id, then a hang), accept, invalid, rejected, timeout (an id, no verdict) or
# neterr. It logs each call. A hang is a child `sleep 61`, as notarytool is a
# child of xcrun, so the test sees whether children are stopped too.
fake="${work}/notarytool"
NOTARY_CMD=("${fake}")
# shellcheck disable=SC1091
. "${work}/notary-submit.sh"
cat >"${fake}" <<'FAKE'
#!/bin/bash
dir="$(dirname "$0")"
echo "$*" >>"${dir}/calls"
n=$(( $(wc -l <"${dir}/calls") ))
what="$(sed -n "${n}p" "${dir}/plan")"
case "${what}" in
	hang) sleep 61 ;;
	hangid) printf '  id: 11111111-2222-3333-4444-555555555555\n'; sleep 61 ;;
	accept) printf 'Conducting pre-submission checks\n  id: 11111111-2222-3333-4444-555555555555\n  status: Accepted\n' ;;
	invalid) printf '  id: 11111111-2222-3333-4444-555555555555\n  status: Invalid\n'; exit 1 ;;
	rejected) printf '  id: 11111111-2222-3333-4444-555555555555\n  status: Rejected\n'; exit 1 ;;
	timeout) printf '  id: 11111111-2222-3333-4444-555555555555\nTimeout of 2s reached\n'; exit 2 ;;
	neterr) echo "Error: The network connection was lost."; exit 1 ;;
esac
FAKE
chmod 755 "${fake}"

failures=0
check() { # check <name> <plan...> -- <want rc> <want calls> <first word of last call> <most seconds>
	local name="$1"
	shift
	: >"${work}/calls"
	: >"${work}/plan"
	while [ "$1" != "--" ]; do
		echo "$1" >>"${work}/plan"
		shift
	done
	shift
	local want_rc="$1" want_calls="$2" want_last="$3" most="$4" rc=0 start end
	NOTARY_SPENT_SECONDS=0
	start=$(date +%s)
	notary_submit app.zip "${work}/out" --key k >"${work}/log" 2>&1 || rc=$?
	end=$(date +%s)
	local calls last took=$((end - start))
	calls=$(($(wc -l <"${work}/calls")))
	last="$(tail -n 1 "${work}/calls" | awk '{print $1}')"
	if [ "${rc}" -ne "${want_rc}" ] || [ "${calls}" -ne "${want_calls}" ] || [ "${last}" != "${want_last}" ] || [ "${took}" -gt "${most}" ]; then
		echo "FAIL ${name}: rc=${rc} calls=${calls} last=${last} took=${took}s (want ${want_rc} ${want_calls} ${want_last} <=${most}s)"
		sed 's/^/     | /' "${work}/log"
		failures=$((failures + 1))
	else
		echo "ok   ${name} (${took}s)"
	fi
}

check "accepted first time" accept -- 0 1 submit 3
check "hang is stopped, then resubmit" hang accept -- 0 2 submit 8
check "network error, then resubmit" neterr accept -- 0 2 submit 3
check "timeout waits on the same id" timeout accept -- 0 2 wait 3
check "hang after an id waits on it" hangid accept -- 0 2 wait 8
check "invalid is final" invalid accept -- 1 1 submit 3
check "rejected is final" rejected accept -- 1 1 submit 3
check "gives up after three attempts" hang hang hang accept -- 1 3 submit 15

# A stopped attempt says so.
if ! grep -q "Stopped after 2s" "${work}/log"; then
	echo "FAIL a stopped attempt does not say it was stopped"
	failures=$((failures + 1))
fi
# The heartbeat shows the wait is alive.
if ! grep -q "Still waiting on the notary service" "${work}/log"; then
	echo "FAIL no heartbeat while waiting"
	failures=$((failures + 1))
fi

# The budget for the run is shared: with 3 seconds left, one hang spends it
# and the next attempt is not made.
: >"${work}/calls"
printf 'hang\naccept\n' >"${work}/plan"
NOTARY_SPENT_SECONDS=0
rc=0
NOTARY_BUDGET_SECONDS=2 notary_submit app.zip "${work}/out" >"${work}/log" 2>&1 || rc=$?
if [ "${rc}" -eq 0 ] || [ "$(wc -l <"${work}/calls")" -ne 1 ] || ! grep -q "budget" "${work}/log"; then
	echo "FAIL the run's budget is not enforced (rc=${rc})"
	failures=$((failures + 1))
else
	echo "ok   the run's budget stops further attempts"
fi
NOTARY_SPENT_SECONDS=0

# The id of the accepted submission is handed back.
: >"${work}/calls"
printf 'accept\n' >"${work}/plan"
notary_submit app.zip "${work}/out" >/dev/null 2>&1
if [ "${NOTARY_SUBMISSION_ID}" != "11111111-2222-3333-4444-555555555555" ]; then
	echo "FAIL submission id: got '${NOTARY_SUBMISSION_ID}'"
	failures=$((failures + 1))
else
	echo "ok   submission id is handed back"
fi

# A stopped attempt leaves nothing running: not the fake, not its child.
sleep 1
if pgrep -f "${work}/notarytool" >/dev/null || pgrep -f "sleep 61" >/dev/null; then
	echo "FAIL a fake notarytool or its child is still running"
	failures=$((failures + 1))
	pkill -f "sleep 61" || true
else
	echo "ok   nothing is left running"
fi

[ "${failures}" -eq 0 ]
