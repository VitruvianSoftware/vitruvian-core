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

set -euo pipefail

if [ "$#" -ne 1 ]; then
	echo "usage: $0 <case>" >&2
	exit 2
fi
case_name="$1"

script="$(dirname "$0")/set_actions_cache_limit.sh"
if [ ! -f "${script}" ]; then
	script="${TEST_SRCDIR}/_main/infrastructure/pulumi/platform/repo-config/set_actions_cache_limit.sh"
fi
if [ ! -f "${script}" ]; then
	echo "cannot locate set_actions_cache_limit.sh" >&2
	exit 1
fi

tmp="${TEST_TMPDIR:-$(mktemp -d)}"
case_dir="${tmp}/${case_name}"
mkdir -p "${case_dir}"
fake_gh="${case_dir}/gh"
call_log="${case_dir}/calls.log"
var_log="${case_dir}/vars.log"

cat >"${fake_gh}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ -z "${GH_TOKEN:-}" ]; then
    echo "fake gh: GH_TOKEN must be set" >&2
    exit 99
fi

cmd="${1:-}"
shift || true

case "${cmd}" in
    api)
        method="GET"
        endpoint=""
        has_input=0
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --method|-X)
                    method="$2"
                    shift 2
                    ;;
                -H|--jq)
                    shift 2
                    ;;
                --input)
                    has_input=1
                    shift 2
                    ;;
                -*)
                    shift
                    ;;
                *)
                    endpoint="$1"
                    shift
                    ;;
            esac
        done
        if [ "${method}" = "PUT" ]; then
            body=""
            if [ "${has_input}" -eq 1 ]; then
                body="$(cat)"
            fi
            printf 'PUT %s %s\n' "${endpoint}" "${body}" >> "${CALL_LOG}"
            if [[ "${endpoint}" == orgs/* ]]; then
                case "${FAKE_ORG_PUT_MODE:-ok}" in
                    402)
                        echo '{"message":"Payment required to increase Actions cache limit","status":"402"}' >&2
                        echo 'gh: Payment required (HTTP 402)' >&2
                        exit 1
                        ;;
                    403)
                        echo '{"message":"Resource not accessible by integration","status":"403"}' >&2
                        echo 'gh: Forbidden (HTTP 403)' >&2
                        exit 1
                        ;;
                    ok)
                        if [ -n "${FAKE_ORG_GET_VALUE_AFTER_PUT:-}" ] && [ -n "${ORG_STATE_FILE:-}" ]; then
                            printf '%s\n' "${FAKE_ORG_GET_VALUE_AFTER_PUT}" > "${ORG_STATE_FILE}"
                        fi
                        echo "${body}"
                        exit 0
                        ;;
                    *)
                        echo "unknown FAKE_ORG_PUT_MODE=${FAKE_ORG_PUT_MODE:-}" >&2
                        exit 98
                        ;;
                esac
            else
                case "${FAKE_PUT_MODE:-ok}" in
                    402)
                        echo '{"message":"Payment required to increase Actions cache limit","status":"402"}' >&2
                        echo 'gh: Payment required (HTTP 402)' >&2
                        exit 1
                        ;;
                    403)
                        echo '{"message":"Resource not accessible by integration","status":"403"}' >&2
                        echo 'gh: Forbidden (HTTP 403)' >&2
                        exit 1
                        ;;
                    422)
                        echo '{"message":"Repository cache size limit must be between 10 and 10.","status":"422"}' >&2
                        echo 'gh: Unprocessable Entity (HTTP 422)' >&2
                        exit 1
                        ;;
                    ok)
                        echo '{"max_cache_size_gb":15}'
                        exit 0
                        ;;
                    *)
                        echo "unknown FAKE_PUT_MODE=${FAKE_PUT_MODE:-}" >&2
                        exit 98
                        ;;
                esac
            fi
        else
            printf 'GET %s\n' "${endpoint}" >> "${CALL_LOG}"
            if [[ "${endpoint}" == orgs/* ]]; then
                case "${FAKE_ORG_GET_MODE:-ok}" in
                    ok)
                        if [ -n "${ORG_STATE_FILE:-}" ] && [ -f "${ORG_STATE_FILE}" ]; then
                            cat "${ORG_STATE_FILE}"
                        else
                            echo "${FAKE_ORG_GET_VALUE:-20}"
                        fi
                        exit 0
                        ;;
                    403)
                        echo '{"message":"Resource not accessible by integration","status":"403"}' >&2
                        echo 'gh: Forbidden (HTTP 403)' >&2
                        exit 1
                        ;;
                    fail)
                        echo 'gh: Internal Server Error (HTTP 500)' >&2
                        exit 1
                        ;;
                    invalid)
                        echo "${FAKE_ORG_GET_VALUE:-null}"
                        exit 0
                        ;;
                    *)
                        echo "unknown FAKE_ORG_GET_MODE=${FAKE_ORG_GET_MODE:-}" >&2
                        exit 98
                        ;;
                esac
            else
                case "${FAKE_GET_MODE:-match}" in
                    match)
                        echo "${FAKE_GET_VALUE:-15}"
                        exit 0
                        ;;
                    mismatch)
                        echo "${FAKE_GET_VALUE:-10}"
                        exit 0
                        ;;
                    fail)
                        echo 'gh: Internal Server Error (HTTP 500)' >&2
                        exit 1
                        ;;
                    invalid)
                        echo "${FAKE_GET_VALUE:-null}"
                        exit 0
                        ;;
                    *)
                        echo "unknown FAKE_GET_MODE=${FAKE_GET_MODE:-}" >&2
                        exit 98
                        ;;
                esac
            fi
        fi
        ;;
    variable)
        sub="${1:-}"
        shift || true
        if [ "${sub}" = "set" ]; then
            printf 'VARIABLE_SET %s\n' "$*" >> "${VAR_LOG}"
            printf 'VARIABLE_SET %s\n' "$*" >> "${CALL_LOG}"
            exit 0
        fi
        echo "fake gh: unexpected variable subcommand ${sub}" >&2
        exit 97
        ;;
    *)
        echo "fake gh: unexpected command ${cmd}" >&2
        exit 96
        ;;
esac
EOF
chmod +x "${fake_gh}"

fail() {
	echo "FAIL [${case_name}]: $*" >&2
	exit 1
}

assert_no_var_set() {
	if [ -s "${var_log}" ]; then
		fail "expected no variable set, got: $(cat "${var_log}")"
	fi
}

assert_var_set() {
	local expected="$1"
	local var_lines want got_var
	if [ ! -s "${var_log}" ]; then
		fail "expected variable set to ${expected}, got no variable set"
	fi
	var_lines="$(wc -l <"${var_log}" | tr -d ' ')"
	if [ "${var_lines}" -ne 1 ]; then
		fail "expected exactly 1 variable set call, got ${var_lines}: $(cat "${var_log}")"
	fi
	want="VARIABLE_SET ACTIONS_CACHE_LIMIT_CONFIRMED_GB --repo VitruvianSoftware/vitruvian-core --body ${expected}"
	got_var="$(<"${var_log}")"
	if [ "${got_var}" != "${want}" ]; then
		fail "got variable set '${got_var}', want '${want}'"
	fi
}

assert_calls() {
	local want="$1"
	local got
	if [ ! -f "${call_log}" ]; then
		got=""
	else
		got="$(<"${call_log}")"
	fi
	if [ "${got}" != "${want}" ]; then
		fail "call log mismatch:
--- got ---
${got}
--- want ---
${want}"
	fi
}

run_case() {
	local limit_file="$1"
	rm -f "${case_dir}/org_state"
	GH="${fake_gh}" \
		GH_TOKEN="fake-app-token" \
		REPO="VitruvianSoftware/vitruvian-core" \
		LIMIT_FILE="${limit_file}" \
		CALL_LOG="${call_log}" \
		VAR_LOG="${var_log}" \
		ORG_STATE_FILE="${case_dir}/org_state" \
		bash "${script}" >"${case_dir}/stdout" 2>"${case_dir}/stderr"
}

limit_file="${case_dir}/limit.txt"

case "${case_name}" in
put_402)
	printf '15\n' >"${limit_file}"
	export FAKE_PUT_MODE=402
	export FAKE_GET_MODE=mismatch
	export FAKE_GET_VALUE=10
	if run_case "${limit_file}"; then
		fail "expected non-zero exit on 402"
	fi
	grep -q '402' "${case_dir}/stderr" || fail "stderr missing 402: $(cat "${case_dir}/stderr")"
	grep -q 'Payment required' "${case_dir}/stderr" || fail "stderr missing payment message: $(cat "${case_dir}/stderr")"
	grep -q '^PUT repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit {"max_cache_size_gb":15}$' "${call_log}" || fail "expected PUT call, got: $(cat "${call_log}")"
	get_count="$(grep -c '^GET repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit$' "${call_log}" || true)"
	if [ "${get_count}" -ne 1 ]; then
		fail "expected exactly 1 GET call after PUT 402, got ${get_count}: $(cat "${call_log}")"
	fi
	assert_var_set 10
	;;
put_403)
	printf '15\n' >"${limit_file}"
	export FAKE_PUT_MODE=403
	export FAKE_GET_MODE=mismatch
	export FAKE_GET_VALUE=10
	if run_case "${limit_file}"; then
		fail "expected non-zero exit on 403"
	fi
	grep -q '403' "${case_dir}/stderr" || fail "stderr missing 403: $(cat "${case_dir}/stderr")"
	grep -q '^PUT repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit {"max_cache_size_gb":15}$' "${call_log}" || fail "expected PUT call, got: $(cat "${call_log}")"
	get_count="$(grep -c '^GET repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit$' "${call_log}" || true)"
	if [ "${get_count}" -ne 1 ]; then
		fail "expected exactly 1 GET call after PUT 403, got ${get_count}: $(cat "${call_log}")"
	fi
	assert_var_set 10
	;;
put_refused_live_get_fails)
	printf '15\n' >"${limit_file}"
	export FAKE_PUT_MODE=402
	export FAKE_GET_MODE=fail
	if run_case "${limit_file}"; then
		fail "expected non-zero exit when PUT 402 and GET fails"
	fi
	grep -q '^PUT repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit {"max_cache_size_gb":15}$' "${call_log}" || fail "expected PUT call, got: $(cat "${call_log}")"
	get_count="$(grep -c '^GET repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit$' "${call_log}" || true)"
	if [ "${get_count}" -ne 1 ]; then
		fail "expected exactly 1 GET call when GET fails, got ${get_count}: $(cat "${call_log}")"
	fi
	grep -q 'unchanged' "${case_dir}/stderr" || fail "stderr missing unchanged message: $(cat "${case_dir}/stderr")"
	assert_no_var_set

	rm -f "${call_log}" "${var_log}"
	export FAKE_PUT_MODE=402
	export FAKE_GET_MODE=invalid
	export FAKE_GET_VALUE=null
	if run_case "${limit_file}"; then
		fail "expected non-zero exit when PUT 402 and GET returns invalid"
	fi
	grep -q '^PUT repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit {"max_cache_size_gb":15}$' "${call_log}" || fail "expected PUT call, got: $(cat "${call_log}")"
	get_count="$(grep -c '^GET repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit$' "${call_log}" || true)"
	if [ "${get_count}" -ne 1 ]; then
		fail "expected exactly 1 GET call when GET returns invalid, got ${get_count}: $(cat "${call_log}")"
	fi
	grep -q 'unchanged' "${case_dir}/stderr" || fail "stderr missing unchanged message: $(cat "${case_dir}/stderr")"
	assert_no_var_set
	;;
readback_timeout)
	printf '15\n' >"${limit_file}"
	export FAKE_PUT_MODE=ok
	export FAKE_GET_MODE=mismatch
	export FAKE_GET_VALUE=10
	export ACTIONS_CACHE_LIMIT_TIMEOUT_SECONDS=1
	export ACTIONS_CACHE_LIMIT_POLL_INTERVAL_SECONDS=1
	if run_case "${limit_file}"; then
		fail "expected non-zero exit on readback timeout"
	fi
	grep -q '^PUT repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit {"max_cache_size_gb":15}$' "${call_log}" || fail "expected PUT call"
	grep -q '^GET repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit$' "${call_log}" || fail "expected GET call"
	assert_var_set 10
	;;
invalid_file)
	export FAKE_PUT_MODE=ok
	for bad in "15GB" "0" "00" "-3" "1.5" "+15" "015" "" "   " $'15\n16'; do
		rm -f "${call_log}" "${var_log}"
		printf '%s\n' "${bad}" >"${limit_file}"
		if run_case "${limit_file}"; then
			fail "accepted invalid value: ${bad}"
		fi
		if [ -s "${call_log}" ]; then
			fail "gh was called for invalid value '${bad}': $(cat "${call_log}")"
		fi
		assert_no_var_set
	done
	# Also test completely empty file (0 bytes)
	rm -f "${call_log}" "${var_log}"
	: >"${limit_file}"
	if run_case "${limit_file}"; then
		fail "accepted empty 0-byte file"
	fi
	if [ -s "${call_log}" ]; then
		fail "gh was called for empty file"
	fi
	assert_no_var_set
	;;
success)
	printf '15\n' >"${limit_file}"
	export FAKE_PUT_MODE=ok
	export FAKE_GET_MODE=match
	export FAKE_GET_VALUE=15
	run_case "${limit_file}" || fail "expected exit 0 on success, stderr=$(cat "${case_dir}/stderr")"
	grep -q '^PUT repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit {"max_cache_size_gb":15}$' "${call_log}" || fail "missing PUT call"
	grep -q '^GET repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit$' "${call_log}" || fail "missing GET call"
	var_lines="$(wc -l <"${var_log}" | tr -d ' ')"
	if [ "${var_lines}" -ne 1 ]; then
		fail "expected exactly 1 variable set call, got ${var_lines}: $(cat "${var_log}")"
	fi
	want='VARIABLE_SET ACTIONS_CACHE_LIMIT_CONFIRMED_GB --repo VitruvianSoftware/vitruvian-core --body 15'
	got_var="$(<"${var_log}")"
	if [ "${got_var}" != "${want}" ]; then
		fail "got variable set '${got_var}', want '${want}'"
	fi
	;;
org_already_sufficient)
	printf '15\n' >"${limit_file}"
	export FAKE_ORG_GET_MODE=ok
	export FAKE_ORG_GET_VALUE=15
	export FAKE_ORG_PUT_MODE=ok
	export FAKE_PUT_MODE=ok
	export FAKE_GET_MODE=match
	export FAKE_GET_VALUE=15
	run_case "${limit_file}" || fail "expected exit 0 when org limit equals 15, stderr=$(cat "${case_dir}/stderr")"
	org_put_count="$(grep -c '^PUT orgs/' "${call_log}" || true)"
	if [ "${org_put_count}" -ne 0 ]; then
		fail "expected 0 org PUT calls when org limit equals 15, got ${org_put_count}: $(cat "${call_log}")"
	fi
	warn_count="$(grep -c '^::warning::' "${case_dir}/stderr" || true)"
	err_count="$(grep -c '^::error::' "${case_dir}/stderr" || true)"
	if [ "${warn_count}" -ne 0 ] || [ "${err_count}" -ne 0 ]; then
		fail "expected 0 warnings and 0 errors, got warn=${warn_count} err=${err_count}: $(cat "${case_dir}/stderr")"
	fi
	assert_calls $'GET orgs/VitruvianSoftware/actions/cache/storage-limit\nPUT repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit {"max_cache_size_gb":15}\nGET repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit\nVARIABLE_SET ACTIONS_CACHE_LIMIT_CONFIRMED_GB --repo VitruvianSoftware/vitruvian-core --body 15'
	assert_var_set 15
	;;
org_raised_then_repo_put)
	printf '15\n' >"${limit_file}"
	export FAKE_ORG_GET_MODE=ok
	export FAKE_ORG_GET_VALUE=10
	export FAKE_ORG_PUT_MODE=ok
	export FAKE_ORG_GET_VALUE_AFTER_PUT=15
	export FAKE_PUT_MODE=ok
	export FAKE_GET_MODE=match
	export FAKE_GET_VALUE=15
	run_case "${limit_file}" || fail "expected exit 0 when org limit is raised from 10 to 15, stderr=$(cat "${case_dir}/stderr")"
	assert_calls $'GET orgs/VitruvianSoftware/actions/cache/storage-limit\nPUT orgs/VitruvianSoftware/actions/cache/storage-limit {"max_cache_size_gb":15}\nGET orgs/VitruvianSoftware/actions/cache/storage-limit\nPUT repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit {"max_cache_size_gb":15}\nGET repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit\nVARIABLE_SET ACTIONS_CACHE_LIMIT_CONFIRMED_GB --repo VitruvianSoftware/vitruvian-core --body 15'
	assert_var_set 15
	;;
org_put_refused)
	printf '15\n' >"${limit_file}"
	export FAKE_ORG_GET_MODE=ok
	export FAKE_ORG_GET_VALUE=10
	export FAKE_ORG_PUT_MODE=403
	export FAKE_PUT_MODE=422
	export FAKE_GET_MODE=mismatch
	export FAKE_GET_VALUE=10
	if run_case "${limit_file}"; then
		fail "expected non-zero exit when org PUT is refused (403)"
	fi
	org_err_count="$(grep -c '^::error::Organization .*10.*Administration' "${case_dir}/stderr" || true)"
	if [ "${org_err_count}" -ne 1 ]; then
		fail "expected 1 org ::error line mentioning 10 and Administration, got ${org_err_count}: $(cat "${case_dir}/stderr")"
	fi
	grep -q 'Settings -> Actions -> General' "${case_dir}/stderr" || fail "stderr missing Settings -> Actions -> General: $(cat "${case_dir}/stderr")"
	assert_calls $'GET orgs/VitruvianSoftware/actions/cache/storage-limit\nPUT orgs/VitruvianSoftware/actions/cache/storage-limit {"max_cache_size_gb":15}\nPUT repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit {"max_cache_size_gb":15}\nGET repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit\nVARIABLE_SET ACTIONS_CACHE_LIMIT_CONFIRMED_GB --repo VitruvianSoftware/vitruvian-core --body 10'
	assert_var_set 10
	;;
org_put_refused_repo_confirmed)
	printf '15\n' >"${limit_file}"
	export FAKE_ORG_GET_MODE=ok
	export FAKE_ORG_GET_VALUE=10
	export FAKE_ORG_PUT_MODE=403
	export FAKE_PUT_MODE=ok
	export FAKE_GET_MODE=match
	export FAKE_GET_VALUE=15
	if run_case "${limit_file}"; then
		fail "expected non-zero exit when org PUT is refused (403) even if repo PUT confirms 15"
	fi
	err_count="$(grep -c '^::error::' "${case_dir}/stderr" || true)"
	org_err_count="$(grep -c '^::error::Organization .*10.*Administration' "${case_dir}/stderr" || true)"
	if [ "${err_count}" -ne 1 ] || [ "${org_err_count}" -ne 1 ]; then
		fail "expected 1 ::error line about org limit (10, Administration), got err=${err_count} org_err=${org_err_count}: $(cat "${case_dir}/stderr")"
	fi
	grep -q 'Settings -> Actions -> General' "${case_dir}/stderr" || fail "stderr missing Settings -> Actions -> General: $(cat "${case_dir}/stderr")"
	assert_calls $'GET orgs/VitruvianSoftware/actions/cache/storage-limit\nPUT orgs/VitruvianSoftware/actions/cache/storage-limit {"max_cache_size_gb":15}\nPUT repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit {"max_cache_size_gb":15}\nGET repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit\nVARIABLE_SET ACTIONS_CACHE_LIMIT_CONFIRMED_GB --repo VitruvianSoftware/vitruvian-core --body 15'
	assert_var_set 15
	;;
org_higher_never_lowered)
	printf '15\n' >"${limit_file}"
	export FAKE_ORG_GET_MODE=ok
	export FAKE_ORG_GET_VALUE=20
	export FAKE_ORG_PUT_MODE=ok
	export FAKE_PUT_MODE=ok
	export FAKE_GET_MODE=match
	export FAKE_GET_VALUE=15
	run_case "${limit_file}" || fail "expected exit 0 when org limit is 20 and repo PUT succeeds, stderr=$(cat "${case_dir}/stderr")"
	org_put_count="$(grep -c '^PUT orgs/' "${call_log}" || true)"
	if [ "${org_put_count}" -ne 0 ]; then
		fail "expected 0 org PUT calls when org limit is 20, got ${org_put_count}: $(cat "${call_log}")"
	fi
	assert_calls $'GET orgs/VitruvianSoftware/actions/cache/storage-limit\nPUT repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit {"max_cache_size_gb":15}\nGET repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit\nVARIABLE_SET ACTIONS_CACHE_LIMIT_CONFIRMED_GB --repo VitruvianSoftware/vitruvian-core --body 15'
	assert_var_set 15

	rm -f "${call_log}" "${var_log}"
	export FAKE_PUT_MODE=402
	export FAKE_GET_MODE=mismatch
	export FAKE_GET_VALUE=10
	if run_case "${limit_file}"; then
		fail "expected non-zero exit when repo PUT fails with 402"
	fi
	org_put_count="$(grep -c '^PUT orgs/' "${call_log}" || true)"
	if [ "${org_put_count}" -ne 0 ]; then
		fail "expected 0 org PUT calls even when repo PUT fails, got ${org_put_count}: $(cat "${call_log}")"
	fi
	assert_calls $'GET orgs/VitruvianSoftware/actions/cache/storage-limit\nPUT repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit {"max_cache_size_gb":15}\nGET repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit\nVARIABLE_SET ACTIONS_CACHE_LIMIT_CONFIRMED_GB --repo VitruvianSoftware/vitruvian-core --body 10'
	assert_var_set 10
	;;
org_get_refused_repo_confirmed)
	printf '15\n' >"${limit_file}"
	export FAKE_ORG_GET_MODE=403
	export FAKE_PUT_MODE=ok
	export FAKE_GET_MODE=match
	export FAKE_GET_VALUE=15
	run_case "${limit_file}" || fail "expected exit 0 when org GET is refused (403) and repo PUT confirms 15, stderr=$(cat "${case_dir}/stderr")"
	org_put_count="$(grep -c '^PUT orgs/' "${call_log}" || true)"
	if [ "${org_put_count}" -ne 0 ]; then
		fail "expected 0 org PUT calls when org GET is refused, got ${org_put_count}: $(cat "${call_log}")"
	fi
	warn_count="$(grep -c '^::warning::' "${case_dir}/stderr" || true)"
	org_warn_count="$(grep -c '^::warning::Could not read organization VitruvianSoftware Actions cache storage limit' "${case_dir}/stderr" || true)"
	err_count="$(grep -c '^::error::' "${case_dir}/stderr" || true)"
	if [ "${warn_count}" -ne 1 ] || [ "${org_warn_count}" -ne 1 ] || [ "${err_count}" -ne 0 ]; then
		fail "expected 1 org ::warning and 0 ::error, got warn=${warn_count} org_warn=${org_warn_count} err=${err_count}: $(cat "${case_dir}/stderr")"
	fi
	assert_calls $'GET orgs/VitruvianSoftware/actions/cache/storage-limit\nPUT repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit {"max_cache_size_gb":15}\nGET repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit\nVARIABLE_SET ACTIONS_CACHE_LIMIT_CONFIRMED_GB --repo VitruvianSoftware/vitruvian-core --body 15'
	assert_var_set 15

	rm -f "${call_log}" "${var_log}"
	export FAKE_ORG_GET_MODE=fail
	run_case "${limit_file}" || fail "expected exit 0 when org GET fails (500) and repo PUT confirms 15, stderr=$(cat "${case_dir}/stderr")"
	org_put_count="$(grep -c '^PUT orgs/' "${call_log}" || true)"
	if [ "${org_put_count}" -ne 0 ]; then
		fail "expected 0 org PUT calls when org GET fails (500), got ${org_put_count}: $(cat "${call_log}")"
	fi
	warn_count="$(grep -c '^::warning::' "${case_dir}/stderr" || true)"
	org_warn_count="$(grep -c '^::warning::Could not read organization VitruvianSoftware Actions cache storage limit' "${case_dir}/stderr" || true)"
	err_count="$(grep -c '^::error::' "${case_dir}/stderr" || true)"
	if [ "${warn_count}" -ne 1 ] || [ "${org_warn_count}" -ne 1 ] || [ "${err_count}" -ne 0 ]; then
		fail "expected 1 org ::warning and 0 ::error on 500, got warn=${warn_count} org_warn=${org_warn_count} err=${err_count}: $(cat "${case_dir}/stderr")"
	fi
	assert_calls $'GET orgs/VitruvianSoftware/actions/cache/storage-limit\nPUT repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit {"max_cache_size_gb":15}\nGET repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit\nVARIABLE_SET ACTIONS_CACHE_LIMIT_CONFIRMED_GB --repo VitruvianSoftware/vitruvian-core --body 15'
	assert_var_set 15
	;;
org_get_refused_repo_refused)
	printf '15\n' >"${limit_file}"
	export FAKE_ORG_GET_MODE=403
	export FAKE_PUT_MODE=422
	export FAKE_GET_MODE=mismatch
	export FAKE_GET_VALUE=10
	if run_case "${limit_file}"; then
		fail "expected non-zero exit when org GET is refused (403) and repo PUT is refused"
	fi
	org_put_count="$(grep -c '^PUT orgs/' "${call_log}" || true)"
	if [ "${org_put_count}" -ne 0 ]; then
		fail "expected 0 org PUT calls when org GET is refused, got ${org_put_count}: $(cat "${call_log}")"
	fi
	warn_count="$(grep -c '^::warning::' "${case_dir}/stderr" || true)"
	org_warn_count="$(grep -c '^::warning::Could not read organization VitruvianSoftware Actions cache storage limit' "${case_dir}/stderr" || true)"
	if [ "${warn_count}" -ne 1 ] || [ "${org_warn_count}" -ne 1 ]; then
		fail "expected 1 org ::warning, got warn=${warn_count} org_warn=${org_warn_count}: $(cat "${case_dir}/stderr")"
	fi
	assert_calls $'GET orgs/VitruvianSoftware/actions/cache/storage-limit\nPUT repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit {"max_cache_size_gb":15}\nGET repos/VitruvianSoftware/vitruvian-core/actions/cache/storage-limit\nVARIABLE_SET ACTIONS_CACHE_LIMIT_CONFIRMED_GB --repo VitruvianSoftware/vitruvian-core --body 10'
	assert_var_set 10
	;;
*)
	echo "unknown case: ${case_name}" >&2
	exit 2
	;;
esac

echo "PASS [${case_name}]"
