#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Tests for record-turn.sh and its Rust port, including side-by-side parity.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNDER_TEST="${1:-${HERE}/record-turn.sh}"
[ -f "${UNDER_TEST}" ] || UNDER_TEST="apps/desktop/antigravity/plugins/receipts-report/hooks/record-turn.sh"
[ -f "${UNDER_TEST}" ] || {
	echo "cannot find record-turn under test" >&2
	exit 1
}
UNDER_TEST="$(cd "$(dirname "${UNDER_TEST}")" && pwd)/$(basename "${UNDER_TEST}")"

REF_SCRIPT="${2:-}"
if [ -n "${REF_SCRIPT}" ] && [ -f "${REF_SCRIPT}" ]; then
	REF_SCRIPT="$(cd "$(dirname "${REF_SCRIPT}")" && pwd)/$(basename "${REF_SCRIPT}")"
fi

PASS=0
FAIL=0
check() {
	if [ "$2" = "0" ]; then
		printf '  PASS  %s\n' "$1"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n' "$1"
		FAIL=$((FAIL + 1))
	fi
}

run_target() {
	local target="$1"
	local home_dir="$2"
	local app_dir="${3:-}"
	if [[ "${target}" == *.sh ]]; then
		if [ -n "${app_dir}" ]; then
			HOME="${home_dir}" ANTIGRAVITY_APP_DATA_DIR="${app_dir}" sh "${target}"
		else
			env -u ANTIGRAVITY_APP_DATA_DIR HOME="${home_dir}" sh "${target}"
		fi
	else
		if [ -n "${app_dir}" ]; then
			HOME="${home_dir}" ANTIGRAVITY_APP_DATA_DIR="${app_dir}" "${target}"
		else
			env -u ANTIGRAVITY_APP_DATA_DIR HOME="${home_dir}" "${target}"
		fi
	fi
}

run_hook() {
	run_target "${UNDER_TEST}" "${SANDBOX}" "${APP_DATA_OVERRIDE:-}"
}

notes() { find "$1" -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }

echo "record-turn_test:"

SANDBOX="$(mktemp -d)"
APP_DATA_OVERRIDE=""
out=$(printf '{"event":"other"}' | run_hook)
[ "${out}" = "{}" ]
check "answers {} for payload without conversationId" "$?"
[ "$(notes "${SANDBOX}")" = "0" ]
check "leaves no note without conversationId" "$?"
rm -rf "${SANDBOX}"

SANDBOX="$(mktemp -d)"
out=$(printf '{"conversationId":"c-101","modelName":"claude-opus-4-6"}' | run_hook)
[ "${out}" = "{}" ]
check "answers {} when conversationId is present" "$?"
[ "$(notes "${SANDBOX}")" = "1" ]
check "leaves one note in receipts-report-inbox" "$?"
note="$(find "${SANDBOX}" -name '*.json')"
case "${note}" in
*/.gemini/antigravity/receipts-report-inbox/*) inbox_ok=0 ;;
*) inbox_ok=1 ;;
esac
check "writes note into receipts-report-inbox" "${inbox_ok}"
grep -q '"conversationId":"c-101"' "${note}"
check "note preserves payload" "$?"
rm -rf "${SANDBOX}"

SANDBOX="$(mktemp -d)"
APP_DATA_OVERRIDE="${SANDBOX}/custom-app"
out=$(printf '{"conversationId":"c-202"}' | run_hook)
ok=1
[ "${out}" = "{}" ] && [ "$(notes "${APP_DATA_OVERRIDE}/receipts-report-inbox")" = "1" ] && ok=0
check "honours ANTIGRAVITY_APP_DATA_DIR" "${ok}"
APP_DATA_OVERRIDE=""
rm -rf "${SANDBOX}"

SANDBOX="/nonexistent/receipts-report-test"
out=$(printf '{"conversationId":"c-303"}' | run_hook)
rc=$?
[ "${rc}" = "0" ] && [ "${out}" = "{}" ]
check "still answers {} and exits 0 when unwritable" "$?"

if [ -n "${REF_SCRIPT}" ] && [ -f "${REF_SCRIPT}" ]; then
	for p in '{"event":"noop"}' '{"conversationId":"c1","stepCount":4}' '{"conversationId":"c2","workspacePaths":["/repo"]}'; do
		s_bin="$(mktemp -d)"
		s_sh="$(mktemp -d)"
		out_bin=$(printf '%s' "${p}" | run_target "${UNDER_TEST}" "${s_bin}")
		rc_bin=$?
		out_sh=$(printf '%s' "${p}" | run_target "${REF_SCRIPT}" "${s_sh}")
		rc_sh=$?
		n_bin="$(notes "${s_bin}")"
		n_sh="$(notes "${s_sh}")"
		parity_ok=1
		if [ "${rc_bin}" = "${rc_sh}" ] && [ "${out_bin}" = "${out_sh}" ] && [ "${n_bin}" = "${n_sh}" ]; then
			if [ "${n_bin}" = "1" ]; then
				c_bin="$(cat "$(find "${s_bin}" -name '*.json')")"
				c_sh="$(cat "$(find "${s_sh}" -name '*.json')")"
				[ "${c_bin}" = "${c_sh}" ] && parity_ok=0
			else
				parity_ok=0
			fi
		fi
		check "parity with shell script for ${p}" "${parity_ok}"
		rm -rf "${s_bin}" "${s_sh}"
	done
fi

echo "${PASS} passed, ${FAIL} failed"
[ "${FAIL}" = "0" ]
