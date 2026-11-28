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

# Tests the notary-submit part of sign-and-notarize.sh with a fake notarytool: a hang is stopped and retried,
# a submission that timed out is waited on again rather than sent twice, a
# verdict of Invalid is final, and attempts are bounded.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Under Bazel the script sits beside this test in the runfiles.
script="${here}/sign-and-notarize.sh"
[ -f "${script}" ] || script="${TEST_SRCDIR:-}/_main/apps/desktop/vitruvian-code/scripts/sign-and-notarize.sh"

work="$(mktemp -d "${TEST_TMPDIR:-/tmp}/notary-test.XXXXXX")"
trap 'rm -rf "${work}"' EXIT

export NOTARY_ATTEMPT_SECONDS=2 NOTARY_ATTEMPTS=3 NOTARY_RETRY_PAUSE=0
# Only the functions between the markers: the rest of the script runs.
sed -n '/^# >>> notary-submit$/,/^# <<< notary-submit$/p' "${script}" >"${work}/notary-submit.sh"
grep -q '^notary_submit()' "${work}/notary-submit.sh" || {
	echo "FAIL no notary-submit block in ${script}"
	exit 1
}

# The fake reads a script of behaviours, one line per call: hang, accept,
# invalid, timeout (an id, no verdict) or neterr. It logs each call.
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
	hang) exec sleep 60 ;;
	accept) printf 'Conducting pre-submission checks\n  id: 11111111-2222-3333-4444-555555555555\n  status: Accepted\n' ;;
	invalid) printf '  id: 11111111-2222-3333-4444-555555555555\n  status: Invalid\n'; exit 1 ;;
	timeout) printf '  id: 11111111-2222-3333-4444-555555555555\nTimeout of 2s reached\n'; exit 2 ;;
	neterr) echo "Error: The network connection was lost."; exit 1 ;;
esac
FAKE
chmod 755 "${fake}"

failures=0
check() { # check <name> <plan...> -- <want rc> <want calls> <want first word of last call>
	local name="$1"
	shift
	: >"${work}/calls"
	: >"${work}/plan"
	while [ "$1" != "--" ]; do
		echo "$1" >>"${work}/plan"
		shift
	done
	shift
	local want_rc="$1" want_calls="$2" want_last="$3" rc=0
	notary_submit app.zip "${work}/out" --key k >/dev/null 2>&1 || rc=$?
	local calls last
	calls=$(($(wc -l <"${work}/calls")))
	last="$(tail -n 1 "${work}/calls" | awk '{print $1}')"
	if [ "${rc}" -ne "${want_rc}" ] || [ "${calls}" -ne "${want_calls}" ] || [ "${last}" != "${want_last}" ]; then
		echo "FAIL ${name}: rc=${rc} calls=${calls} last=${last} (want ${want_rc} ${want_calls} ${want_last})"
		failures=$((failures + 1))
	else
		echo "ok   ${name}"
	fi
}

check "accepted first time" accept -- 0 1 submit
check "hang is stopped, then resubmit" hang accept -- 0 2 submit
check "network error, then resubmit" neterr accept -- 0 2 submit
check "timeout waits on the same id" timeout accept -- 0 2 wait
check "invalid is final" invalid accept -- 1 1 submit
check "gives up after three attempts" hang hang hang accept -- 1 3 submit

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

# A stopped attempt leaves no process behind.
sleep 1
if pgrep -f "${work}/notarytool" >/dev/null; then
	echo "FAIL a fake notarytool is still running"
	failures=$((failures + 1))
fi

[ "${failures}" -eq 0 ]
