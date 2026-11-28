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

# Signs, notarizes, staples, and verifies Vitruvian Code's macOS release bundles
# (`Vitruvian Code.app`, the standalone `vitruvian-code-tool` Mach-O, and the
# `.dmg` disk images).
#
# Modes (controlled ONLY by explicit SIGNING; never inferred from missing secrets):
#   SIGNING=developer-id    Default for releases. Requires all 5 VITRUVIAN_*
#                           secrets, imports the .p12 into an ephemeral keychain
#                           that is deleted on exit even on failure, signs with
#                           Hardened Runtime + timestamp, notarizes via
#                           notarytool, staples, and checks Gatekeeper (spctl).
#   SIGNING=local-keychain  Local smoke testing with an existing "Developer ID
#                           Application" identity in the user's keychain. Set
#                           NOTARIZE=0 to skip notarization/stapling/spctl.
#   SIGNING=adhoc           Explicit opt-out used ONLY by the monorepo mirror
#                           rehearsal workflow (.github/workflows/vitruvian-code-mirror-toolchain.yaml).

set -euo pipefail
set +x
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

SCRIPT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_ENTITLEMENTS="${VITRUVIAN_CODE_ENTITLEMENTS:-${REPO_ROOT}/macos/Resources/VitruvianCode.entitlements}"
NODE_ENTITLEMENTS="${VITRUVIAN_CODE_NODE_ENTITLEMENTS:-${REPO_ROOT}/macos/Resources/node.entitlements}"

SIGNING_MODE="${SIGNING:-developer-id}"
WORK_DIR=""
TMP_KEYCHAIN=""
NOTARY_KEY_FILE=""
KEYCHAIN_RESTORE_NEEDED=""
ORIG_KEYCHAINS=()
SIGN_IDENTITY=""
DO_NOTARIZE=0
# Apps Gatekeeper (spctl) refused after notarization and stapling. Filled by
# verify_app_gatekeeper; run_apps fails once, at the end, naming all of them.
GATEKEEPER_REJECTED=()

cleanup() {
	set +e
	trap - EXIT INT TERM
	if [ -n "${KEYCHAIN_RESTORE_NEEDED}" ]; then
		if [ "${#ORIG_KEYCHAINS[@]}" -gt 0 ]; then
			/usr/bin/security list-keychains -d user -s "${ORIG_KEYCHAINS[@]}" >/dev/null 2>&1 || true
		fi
	fi
	if [ -n "${TMP_KEYCHAIN}" ]; then
		/usr/bin/security delete-keychain "${TMP_KEYCHAIN}" >/dev/null 2>&1 || true
	fi
	if [ -n "${WORK_DIR}" ] && [ -d "${WORK_DIR}" ]; then
		/bin/rm -rf "${WORK_DIR}"
	fi
}

on_exit() {
	local rc=$?
	cleanup
	exit "${rc}"
}

on_int() {
	cleanup
	exit 130
}

on_term() {
	cleanup
	exit 143
}

trap on_exit EXIT
trap on_int INT
trap on_term TERM

usage() {
	/bin/cat <<'EOF'
Usage:
  sign-and-notarize.sh apps [--entitlements-app <app.app>]... [--plain-app <app.app>]... [--macho <binary>]... [--node-macho <binary>]...
  sign-and-notarize.sh dmgs <dmg>...
EOF
}

usage_error() {
	local msg="${1:-}"
	if [ -n "${msg}" ]; then
		echo "error: ${msg}" >&2
	fi
	usage >&2
	exit 2
}

fail_error() {
	local msg="$1"
	if [ -n "${GITHUB_ACTIONS:-}" ]; then
		echo "::error::${msg}"
	else
		echo "error: ${msg}" >&2
	fi
	exit 1
}

decode_base64_to_file() {
	local raw="$1"
	local dest="$2"
	local cleaned
	cleaned="$(/usr/bin/tr -d ' \r\n\t' <<<"${raw}")"
	(
		umask 077
		if printf '%s' "${cleaned}" | /usr/bin/base64 --decode >"${dest}" 2>/dev/null; then
			:
		elif printf '%s' "${cleaned}" | /usr/bin/base64 -D >"${dest}" 2>/dev/null; then
			:
		else
			exit 1
		fi
	) || fail_error "Failed to base64-decode credential into temporary file $(/usr/bin/basename "${dest}")."
	/bin/chmod 600 "${dest}"
}

write_notary_key() {
	local raw="$1"
	local dest="$2"
	case "${raw}" in
	*"-----BEGIN"*)
		(
			umask 077
			printf '%s\n' "${raw}" >"${dest}"
		)
		/bin/chmod 600 "${dest}"
		;;
	*)
		decode_base64_to_file "${raw}" "${dest}"
		;;
	esac
	if ! /usr/bin/grep -q -- "-----BEGIN" "${dest}"; then
		fail_error "VITRUVIAN_NOTARY_API_KEY_P8 did not decode to a PEM private key."
	fi
}

setup_credentials() {
	WORK_DIR="$(/usr/bin/mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/vc-sign.XXXXXX")"
	/bin/chmod 700 "${WORK_DIR}"

	case "${SIGNING_MODE}" in
	developer-id)
		local missing=0
		local var
		for var in \
			VITRUVIAN_SIGNING_CERT_P12 \
			VITRUVIAN_SIGNING_CERT_PASSWORD \
			VITRUVIAN_NOTARY_API_KEY_P8 \
			VITRUVIAN_NOTARY_KEY_ID \
			VITRUVIAN_NOTARY_ISSUER_ID; do
			if [ -z "${!var:-}" ]; then
				if [ -n "${GITHUB_ACTIONS:-}" ]; then
					echo "::error::Missing required secret ${var} in vitruvian-code-release environment; refusing to publish unsigned."
				else
					echo "error: Missing required secret ${var}; refusing to publish unsigned." >&2
				fi
				missing=1
			fi
		done
		if [ "${missing}" -ne 0 ]; then
			exit 1
		fi

		while IFS= read -r kc_line; do
			local kc_trimmed
			kc_trimmed="$(/usr/bin/sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//' <<<"${kc_line}")"
			if [ -n "${kc_trimmed}" ]; then
				ORIG_KEYCHAINS+=("${kc_trimmed}")
			fi
		done < <(/usr/bin/security list-keychains -d user)

		local p12_file="${WORK_DIR}/signing.p12"
		decode_base64_to_file "${VITRUVIAN_SIGNING_CERT_P12}" "${p12_file}"

		local raw_rand kc_pass
		raw_rand="$(LC_ALL=C /usr/bin/head -c 48 /dev/urandom | /usr/bin/base64 | /usr/bin/tr -dc 'A-Za-z0-9')"
		raw_rand="${raw_rand%%$'\n'*}"
		kc_pass="${raw_rand:0:24}"
		if [ "${#kc_pass}" -lt 16 ]; then
			fail_error "Failed to generate ephemeral keychain password."
		fi
		TMP_KEYCHAIN="${WORK_DIR}/vitruvian-code-signing.keychain-db"

		# macOS `/usr/bin/security` accepts no password via stdin or env var (-P/-u open GUI prompts); ephemeral runner, the keychain password is random per run, and GitHub masks secrets.
		/usr/bin/security create-keychain -p "${kc_pass}" "${TMP_KEYCHAIN}"
		/bin/chmod 600 "${TMP_KEYCHAIN}"
		/usr/bin/security set-keychain-settings -lut 21600 "${TMP_KEYCHAIN}"
		/usr/bin/security unlock-keychain -p "${kc_pass}" "${TMP_KEYCHAIN}"
		/usr/bin/security import "${p12_file}" \
			-k "${TMP_KEYCHAIN}" \
			-P "${VITRUVIAN_SIGNING_CERT_PASSWORD}" \
			-T /usr/bin/codesign \
			-T /usr/bin/security >/dev/null
		/bin/rm -f "${p12_file}"

		/usr/bin/security set-key-partition-list \
			-S apple-tool:,apple:,codesign: \
			-s -k "${kc_pass}" "${TMP_KEYCHAIN}" >/dev/null

		KEYCHAIN_RESTORE_NEEDED=1
		if [ "${#ORIG_KEYCHAINS[@]}" -gt 0 ]; then
			/usr/bin/security list-keychains -d user -s "${TMP_KEYCHAIN}" "${ORIG_KEYCHAINS[@]}"
		else
			/usr/bin/security list-keychains -d user -s "${TMP_KEYCHAIN}"
		fi

		local listing
		listing="$(/usr/bin/security find-identity -v -p codesigning "${TMP_KEYCHAIN}")"
		SIGN_IDENTITY="$(/usr/bin/awk '/Developer ID Application:/ { print $2; exit }' <<<"${listing}")"
		local identity_label
		identity_label="$(/usr/bin/awk -F'"' '/Developer ID Application:/ { print $2; exit }' <<<"${listing}")"
		if [ -z "${SIGN_IDENTITY}" ]; then
			fail_error "Imported signing certificate in temporary keychain contains no valid 'Developer ID Application' identity."
		fi
		echo "==> Imported signing identity into temporary keychain: ${identity_label}"

		NOTARY_KEY_FILE="${WORK_DIR}/AuthKey.p8"
		write_notary_key "${VITRUVIAN_NOTARY_API_KEY_P8}" "${NOTARY_KEY_FILE}"
		DO_NOTARIZE=1
		;;

	local-keychain)
		local listing
		listing="$(/usr/bin/security find-identity -v -p codesigning)"
		SIGN_IDENTITY="$(/usr/bin/awk '/Developer ID Application:/ { print $2; exit }' <<<"${listing}")"
		local identity_label
		identity_label="$(/usr/bin/awk -F'"' '/Developer ID Application:/ { print $2; exit }' <<<"${listing}")"
		if [ -z "${SIGN_IDENTITY}" ]; then
			fail_error "SIGNING=local-keychain found no valid 'Developer ID Application' identity in the user keychain."
		fi
		echo "==> Using local keychain signing identity: ${identity_label}"
		if [ "${NOTARIZE:-0}" = "1" ]; then
			if [ -z "${VITRUVIAN_NOTARY_API_KEY_P8:-}" ] || [ -z "${VITRUVIAN_NOTARY_KEY_ID:-}" ] || [ -z "${VITRUVIAN_NOTARY_ISSUER_ID:-}" ]; then
				fail_error "NOTARIZE=1 requires VITRUVIAN_NOTARY_API_KEY_P8, VITRUVIAN_NOTARY_KEY_ID, and VITRUVIAN_NOTARY_ISSUER_ID."
			fi
			NOTARY_KEY_FILE="${WORK_DIR}/AuthKey.p8"
			write_notary_key "${VITRUVIAN_NOTARY_API_KEY_P8}" "${NOTARY_KEY_FILE}"
			DO_NOTARIZE=1
		else
			DO_NOTARIZE=0
		fi
		;;

	adhoc)
		echo "==> SIGNING=adhoc: rehearsal mode enabled (ad-hoc signing, notarization skipped)."
		SIGN_IDENTITY="-"
		DO_NOTARIZE=0
		;;

	*)
		fail_error "Unsupported SIGNING='${SIGNING_MODE}' (expected developer-id, local-keychain, or adhoc)."
		;;
	esac
}

codesign_leaf() {
	local target="$1"
	local identifier="${2:-}"
	local entitlements="${3:-}"
	local args=(--force)
	if [ "${SIGNING_MODE}" != "adhoc" ]; then
		args+=(--options runtime --timestamp)
	fi
	if [ -n "${identifier}" ]; then
		args+=(--identifier "${identifier}")
	fi
	if [ -n "${entitlements}" ]; then
		[ -f "${entitlements}" ] || fail_error "Entitlements file not found: ${entitlements}"
		args+=(--entitlements "${entitlements}")
	fi
	if [ "${SIGNING_MODE}" = "adhoc" ]; then
		args+=(--sign -)
	else
		args+=(--sign "${SIGN_IDENTITY}")
	fi
	/usr/bin/codesign "${args[@]}" "${target}"
}

clear_xattrs() {
	local target="$1"
	/usr/bin/find "${target}" -print0 | /usr/bin/xargs -0 /usr/bin/xattr -c -s 2>/dev/null || true
}

read_bundle_executable() {
	local info_plist="$1"
	if [ ! -f "${info_plist}" ]; then
		fail_error "Bundle Info.plist not found: ${info_plist}"
	fi
	local exec_name=""
	if [ -x /usr/libexec/PlistBuddy ]; then
		exec_name="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "${info_plist}" 2>/dev/null || true)"
	fi
	if [ -z "${exec_name}" ]; then
		exec_name="$(/usr/bin/awk '
			/<key>[[:space:]]*CFBundleExecutable[[:space:]]*<\/key>/ { found=1; next }
			found && /<string>/ {
				sub(/^.*<string>/, "")
				sub(/<\/string>.*$/, "")
				print
				exit
			}
		' "${info_plist}")"
	fi
	if [ -z "${exec_name}" ]; then
		fail_error "CFBundleExecutable missing in ${info_plist}"
	fi
	printf '%s\n' "${exec_name}"
}

sign_app_inside_out() {
	local app="$1"
	local entitlements="${2:-}"

	if [ ! -d "${app}" ]; then
		fail_error "App bundle not found: ${app}"
	fi
	# Everything below compares paths as text (the main executable, the Node helpers),
	# so spell the app one way: no trailing or doubled slashes, no ./ or ../, no
	# symlinks.
	app="$(cd "${app}" && /bin/pwd -P)"
	if [ -n "${entitlements}" ] && [ ! -f "${entitlements}" ]; then
		fail_error "Entitlements file not found: ${entitlements}"
	fi

	local main_exec
	main_exec="$(read_bundle_executable "${app}/Contents/Info.plist")"
	local main_exec_path="${app}/Contents/MacOS/${main_exec}"

	/bin/chmod -R u+w "${app}"
	clear_xattrs "${app}"

	# 1. Sign nested regular Mach-O files (helpers, dylibs, and any non-main
	#    Mach-O inside Contents/MacOS) inside-out, skipping ONLY the main
	#    executable (CFBundleExecutable), which is signed with the bundle below.
	local file_desc
	while IFS= read -r candidate; do
		[ -n "${candidate}" ] || continue
		if [ "${candidate}" = "${main_exec_path}" ]; then
			continue
		fi
		file_desc="$(/usr/bin/file -b "${candidate}" 2>/dev/null || true)"
		case "${file_desc}" in
		*Mach-O*)
			# Every Node helper gets the JIT entitlements: the single `node` of a
			# per-architecture app, and the two thin copies (`node-arm64`,
			# `node-x86_64`) the universal app ships in place of one fat `node`.
			if [ "${candidate}" = "${app}/Contents/Helpers/node" ] ||
				[ "${candidate}" = "${app}/Contents/Helpers/node-arm64" ] ||
				[ "${candidate}" = "${app}/Contents/Helpers/node-x86_64" ]; then
				echo "    Signing nested Node helper with JIT entitlements: ${candidate}"
				codesign_leaf "${candidate}" "com.vitruviansoftware.code.node" "${NODE_ENTITLEMENTS}"
			else
				echo "    Signing nested Mach-O: ${candidate}"
				codesign_leaf "${candidate}"
			fi
			;;
		esac
	done < <(/usr/bin/find "${app}/Contents" -depth -type f)

	# 2. Sign nested frameworks, XPC services, or helper app bundles inside-out.
	while IFS= read -r nested_bundle; do
		[ -n "${nested_bundle}" ] || continue
		echo "    Signing nested bundle: ${nested_bundle}"
		codesign_leaf "${nested_bundle}"
	done < <(/usr/bin/find "${app}/Contents" -depth -type d \( -name '*.framework' -o -name '*.xpc' -o -name '*.app' \))

	# 3. Sign the top-level .app bundle.
	echo "==> Signing app bundle: ${app}"
	if [ "${SIGNING_MODE}" = "adhoc" ]; then
		if [ -n "${entitlements}" ]; then
			/usr/bin/codesign --force --entitlements "${entitlements}" --sign - "${app}"
		else
			/usr/bin/codesign --force --sign - "${app}"
		fi
	else
		if [ -n "${entitlements}" ]; then
			/usr/bin/codesign --force --options runtime --timestamp --entitlements "${entitlements}" --sign "${SIGN_IDENTITY}" "${app}"
		else
			/usr/bin/codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" "${app}"
		fi
	fi

	/usr/bin/codesign --verify --deep --strict --verbose=2 "${app}"
}

# >>> notary-submit
# One notary submission that can neither hang the release nor fail it on a
# network blip. scripts/notary-submit_test.sh tests the part between the
# notary-submit markers with a fake notarytool.
#
# On 2026-11-28 the 1.51.0 release sat for 55 minutes at notarytool's
# "initiating connection to the Apple notary service" and the job hit its
# 60-minute limit. Each attempt therefore runs under a watchdog, and all
# attempts in one run of this script share a budget, so even repeated hangs
# end well inside the job's limit (two runs of the script per release).

# Seconds one attempt may take, how many attempts, the pause before the next
# one (times the attempt number), and the seconds every attempt in this run
# may take together. Overridable for the test.
NOTARY_ATTEMPT_SECONDS="${NOTARY_ATTEMPT_SECONDS:-600}"
NOTARY_ATTEMPTS="${NOTARY_ATTEMPTS:-3}"
NOTARY_RETRY_PAUSE="${NOTARY_RETRY_PAUSE:-30}"
NOTARY_BUDGET_SECONDS="${NOTARY_BUDGET_SECONDS:-1200}"
NOTARY_HEARTBEAT_SECONDS="${NOTARY_HEARTBEAT_SECONDS:-60}"
NOTARY_SPENT_SECONDS=0

# The notarytool command. The test points it at a fake.
if [ -z "${NOTARY_CMD+x}" ]; then NOTARY_CMD=(/usr/bin/xcrun notarytool); fi

# run_with_watchdog <seconds> <out_file> <command...>
# Runs the command with its output in <out_file>, printing a line every
# NOTARY_HEARTBEAT_SECONDS while it runs and its output when it ends. Past
# <seconds> it stops the command and the children it started (xcrun runs
# notarytool as its child): TERM, then KILL 10 seconds later. Returns the
# command's status, or 124 when it was stopped.
run_with_watchdog() {
	local seconds="$1" out_file="$2"
	shift 2
	"$@" >"${out_file}" 2>&1 &
	local pid=$! waited=0 stopped=0 rc=0
	while /bin/kill -0 "${pid}" 2>/dev/null; do
		if [ "${waited}" -ge "${seconds}" ]; then
			stopped=1
			local kids
			kids="$(/usr/bin/pgrep -P "${pid}" | /usr/bin/tr '\n' ' ' || true)"
			# shellcheck disable=SC2086 # kids is a list of pids
			/bin/kill -TERM ${kids} "${pid}" 2>/dev/null || true
			local grace=0
			while [ "${grace}" -lt 10 ] && /bin/kill -0 "${pid}" 2>/dev/null; do
				/bin/sleep 1
				grace=$((grace + 1))
			done
			waited=$((waited + grace))
			# shellcheck disable=SC2086
			/bin/kill -KILL ${kids} "${pid}" 2>/dev/null || true
			break
		fi
		/bin/sleep 1
		waited=$((waited + 1))
		if [ "${NOTARY_HEARTBEAT_SECONDS}" -gt 0 ] && [ $((waited % NOTARY_HEARTBEAT_SECONDS)) -eq 0 ]; then
			echo "==> Still waiting on the notary service (${waited}s)..."
		fi
	done
	wait "${pid}" || rc=$?
	NOTARY_SPENT_SECONDS=$((NOTARY_SPENT_SECONDS + waited))
	/bin/cat "${out_file}"
	if [ "${stopped}" -eq 1 ]; then
		echo "==> Stopped after ${seconds}s with no answer from the notary service."
		return 124
	fi
	return "${rc}"
}

# notary_submit <upload> <out_file> <auth args...>
# Leaves the last attempt's output in <out_file>, the submission's id (when
# one was created) in NOTARY_SUBMISSION_ID, and returns 0 once Apple accepts
# the upload. A verdict (Invalid, Rejected) is final and not retried. A hang
# or a network error is retried: by waiting on the same submission when one
# was created, otherwise by submitting again. notarytool's own --timeout is
# not used: it bounds only the wait for a verdict, not the upload.
notary_submit() {
	local upload="$1" out_file="$2"
	shift 2
	local attempt=1 sub_id="" rc left seconds found
	NOTARY_SUBMISSION_ID=""
	while :; do
		left=$((NOTARY_BUDGET_SECONDS - NOTARY_SPENT_SECONDS))
		if [ "${left}" -le 0 ]; then
			echo "==> The notary budget of ${NOTARY_BUDGET_SECONDS}s for this run is spent."
			return 1
		fi
		seconds="${NOTARY_ATTEMPT_SECONDS}"
		[ "${left}" -lt "${seconds}" ] && seconds="${left}"
		rc=0
		if [ -n "${sub_id}" ]; then
			echo "==> Waiting again on notary submission ${sub_id} (attempt ${attempt}/${NOTARY_ATTEMPTS})..."
			run_with_watchdog "${seconds}" "${out_file}" \
				"${NOTARY_CMD[@]}" wait "${sub_id}" "$@" || rc=$?
		else
			[ "${attempt}" -gt 1 ] && echo "==> Submitting again (attempt ${attempt}/${NOTARY_ATTEMPTS})..."
			run_with_watchdog "${seconds}" "${out_file}" \
				"${NOTARY_CMD[@]}" submit "${upload}" "$@" --wait || rc=$?
		fi
		# notarytool prints the submission as an indented "id: <uuid>" line.
		# If a stopped attempt never printed it, the retry submits again.
		found="$(/usr/bin/awk '/^[[:space:]]*id:[[:space:]]/ { print $2; exit }' "${out_file}" || true)"
		if [ -n "${found}" ]; then
			sub_id="${found}"
			NOTARY_SUBMISSION_ID="${sub_id}"
		fi
		if [ "${rc}" -eq 0 ] && /usr/bin/grep -q "status: Accepted" "${out_file}"; then
			return 0
		fi
		if /usr/bin/grep -qE "status: (Invalid|Rejected)" "${out_file}"; then
			return 1
		fi
		if [ "${attempt}" -ge "${NOTARY_ATTEMPTS}" ]; then
			return 1
		fi
		echo "::warning::Notarization of $(/usr/bin/basename "${upload}") got no verdict (attempt ${attempt}/${NOTARY_ATTEMPTS}); trying again."
		# The pause counts against the budget too, and never outlasts it.
		local pause=$((NOTARY_RETRY_PAUSE * attempt))
		left=$((NOTARY_BUDGET_SECONDS - NOTARY_SPENT_SECONDS))
		[ "${pause}" -gt "${left}" ] && pause="${left}"
		[ "${pause}" -gt 0 ] && /bin/sleep "${pause}"
		NOTARY_SPENT_SECONDS=$((NOTARY_SPENT_SECONDS + pause))
		attempt=$((attempt + 1))
	done
}

# notary_log <submission id> <auth args...>
# Prints Apple's log for a submission, to help explain a failure. Bounded to
# two minutes, and never fails the caller.
notary_log() {
	local sub_id="$1"
	shift
	run_with_watchdog 120 "${WORK_DIR}/notary-log-$$.txt" "${NOTARY_CMD[@]}" log "${sub_id}" "$@" || true
	/bin/rm -f "${WORK_DIR}/notary-log-$$.txt"
}
# <<< notary-submit

# Submits one file to the notary service and fails unless Apple accepts it.
# $3 (optional) is the path the submission is FOR when that is not the file
# uploaded (an app is zipped first). An accepted submission's ID is kept in
# ${WORK_DIR}/submissions.tsv as "<id><TAB><path>" so that a later Gatekeeper
# rejection can ask Apple for that submission's log.
notarytool_submit_and_require_accepted() {
	local submit_path="$1"
	local label="$2"
	local for_path="${3:-${submit_path}}"
	local out_file="${WORK_DIR}/notary-$(/bin/date +%s)-$$.log"

	echo "==> Submitting ${label} to Apple notary service..."
	local rc=0
	# notary_submit (above) bounds each attempt and retries a hang or a
	# network error.
	notary_submit "${submit_path}" "${out_file}" \
		--key "${NOTARY_KEY_FILE}" \
		--key-id "${VITRUVIAN_NOTARY_KEY_ID}" \
		--issuer "${VITRUVIAN_NOTARY_ISSUER_ID}" || rc=$?

	# notary_submit read the submission ID from notarytool's "id: <uuid>" line.
	local sub_id
	sub_id="${NOTARY_SUBMISSION_ID:-}"

	if [ "${rc}" -ne 0 ] || ! /usr/bin/grep -q "status: Accepted" "${out_file}"; then
		if [ -n "${sub_id}" ]; then
			echo "==> Fetching Apple notary log for submission ${sub_id}:" >&2
			notary_log "${sub_id}" \
				--key "${NOTARY_KEY_FILE}" \
				--key-id "${VITRUVIAN_NOTARY_KEY_ID}" \
				--issuer "${VITRUVIAN_NOTARY_ISSUER_ID}" >&2
		fi
		/bin/rm -f "${out_file}"
		fail_error "Notarization failed for ${label}."
	fi
	if [ -n "${sub_id}" ]; then
		printf '%s\t%s\n' "${sub_id}" "${for_path}" >>"${WORK_DIR}/submissions.tsv"
	fi
	/bin/rm -f "${out_file}"
}

# Prints the accepted notary submission ID recorded for a path (the last one,
# if it was submitted twice), or nothing.
submission_id_for() {
	[ -f "${WORK_DIR}/submissions.tsv" ] || return 0
	WANT_PATH="$1" /usr/bin/awk -F '\t' '$2 == ENVIRON["WANT_PATH"] { id = $1 } END { if (id != "") print id }' "${WORK_DIR}/submissions.tsv"
}

notarize_and_staple_app() {
	local app="$1"
	local idx="$2"
	local base
	base="$(/usr/bin/basename "${app}")"
	local zip_path="${WORK_DIR}/app-${idx}.zip"

	clear_xattrs "${app}"
	/usr/bin/codesign --verify --deep --strict "${app}"
	/usr/bin/ditto -c -k --keepParent "${app}" "${zip_path}"
	notarytool_submit_and_require_accepted "${zip_path}" "${base}" "${app}"
	/bin/rm -f "${zip_path}"

	echo "==> Stapling notarization ticket to ${app}..."
	/usr/bin/xcrun stapler staple "${app}"
	/usr/bin/xcrun stapler validate "${app}"
}

# Prints the code signature, the cdhash of each architecture slice (the notary
# ticket lists the cdhashes Apple notarized, so these can be compared with it)
# and the entitlements of one signed file. Every command is allowed to fail.
describe_signed_file() {
	local signed="$1"
	local arch
	echo "--- ${signed}"
	/usr/bin/codesign -dvvv --entitlements - "${signed}" 2>&1 || true
	for arch in arm64 x86_64; do
		echo "    cdhash (${arch} slice):"
		/usr/bin/codesign -dvvv -a "${arch}" "${signed}" 2>&1 | /usr/bin/grep -E '^(CDHash|CandidateCDHash)' || true
	done
}

# Explains why Gatekeeper rejected an app that was signed, notarized and
# stapled. Gatekeeper only says "Unnotarized Developer ID", not which part it
# objects to, so this gathers what is needed to tell: macOS's own verdict per
# component, the stapled ticket, the signature of the main executable and every
# helper, and Apple's list of notarized cdhashes. It never prints credentials.
# Nothing here may fail the script; the caller fails on the rejection itself.
print_gatekeeper_diagnostics() {
	local app="$1"
	local sub_id
	sub_id="$(submission_id_for "${app}" || true)"

	echo "::group::Gatekeeper diagnostics for ${app}"
	if [ -x /usr/bin/syspolicy_check ]; then
		echo "--- syspolicy_check distribution (names the component Gatekeeper objects to)"
		/usr/bin/syspolicy_check distribution "${app}" 2>&1 || true
	else
		echo "--- syspolicy_check is not installed on this runner; skipped"
	fi
	echo "--- spctl --raw"
	/usr/sbin/spctl -a -vvvv -t exec --raw "${app}" 2>&1 || true
	echo "--- stapler validate"
	/usr/bin/xcrun stapler validate -v "${app}" 2>&1 || true
	echo "--- codesign on the app bundle"
	/usr/bin/codesign -d --verbose=4 "${app}" 2>&1 || true

	local plist="${app}/Contents/Info.plist"
	local main_exec=""
	if [ -f "${plist}" ]; then
		main_exec="$(read_bundle_executable "${plist}" 2>/dev/null || true)"
	fi
	if [ -n "${main_exec}" ] && [ -f "${app}/Contents/MacOS/${main_exec}" ]; then
		describe_signed_file "${app}/Contents/MacOS/${main_exec}"
	fi
	if [ -d "${app}/Contents/Helpers" ]; then
		local helper
		while IFS= read -r helper; do
			[ -n "${helper}" ] || continue
			case "$(/usr/bin/file -b "${helper}" 2>/dev/null || true)" in
			*Mach-O*) describe_signed_file "${helper}" ;;
			esac
		done < <(/usr/bin/find "${app}/Contents/Helpers" -type f 2>/dev/null || true)
	fi

	if [ -n "${sub_id}" ]; then
		echo "--- Apple notary log for submission ${sub_id} (ticketContents lists every notarized cdhash)"
		notary_log "${sub_id}" \
			--key "${NOTARY_KEY_FILE}" \
			--key-id "${VITRUVIAN_NOTARY_KEY_ID}" \
			--issuer "${VITRUVIAN_NOTARY_ISSUER_ID}" 2>&1
	else
		echo "--- no accepted notary submission ID was recorded for ${app}"
	fi
	echo "::endgroup::"
}

# Asks Gatekeeper about one notarized app. A rejection prints the diagnostics
# and is recorded; it does not stop the script, so every app gets checked.
verify_app_gatekeeper() {
	local app="$1"
	if /usr/sbin/spctl -a -vv -t exec "${app}"; then
		return 0
	fi
	echo "==> Gatekeeper REJECTED ${app}"
	GATEKEEPER_REJECTED+=("${app}")
	print_gatekeeper_diagnostics "${app}"
}

run_apps() {
	local entitled_apps=()
	local plain_apps=()
	local machos=()
	local node_machos=()

	if [ "$#" -eq 0 ]; then
		usage_error
	fi

	while [ "$#" -gt 0 ]; do
		case "$1" in
		--entitlements-app)
			[ "$#" -ge 2 ] || usage_error "--entitlements-app requires a path"
			entitled_apps+=("$2")
			shift 2
			;;
		--plain-app)
			[ "$#" -ge 2 ] || usage_error "--plain-app requires a path"
			plain_apps+=("$2")
			shift 2
			;;
		--macho)
			[ "$#" -ge 2 ] || usage_error "--macho requires a path"
			machos+=("$2")
			shift 2
			;;
		--node-macho)
			[ "$#" -ge 2 ] || usage_error "--node-macho requires a path"
			node_machos+=("$2")
			shift 2
			;;
		*)
			usage_error "Unknown apps argument: $1"
			;;
		esac
	done

	if [ "${#entitled_apps[@]}" -eq 0 ] && [ "${#plain_apps[@]}" -eq 0 ] && [ "${#machos[@]}" -eq 0 ] && [ "${#node_machos[@]}" -eq 0 ]; then
		usage_error
	fi

	setup_credentials

	local app
	if [ "${#entitled_apps[@]}" -gt 0 ]; then
		for app in "${entitled_apps[@]}"; do
			sign_app_inside_out "${app}" "${DEFAULT_ENTITLEMENTS}"
		done
	fi

	if [ "${#plain_apps[@]}" -gt 0 ]; then
		for app in "${plain_apps[@]}"; do
			sign_app_inside_out "${app}" ""
		done
	fi

	local bin
	if [ "${#machos[@]}" -gt 0 ]; then
		for bin in "${machos[@]}"; do
			[ -f "${bin}" ] || fail_error "Mach-O binary not found: ${bin}"
			/bin/chmod u+w "${bin}"
			/usr/bin/xattr -c "${bin}" 2>/dev/null || true
			echo "==> Signing standalone Mach-O: ${bin}"
			codesign_leaf "${bin}" "com.vitruviansoftware.code.tool"
			/usr/bin/codesign --verify --strict --verbose=2 "${bin}"
		done
	fi

	if [ "${#node_machos[@]}" -gt 0 ]; then
		for bin in "${node_machos[@]}"; do
			[ -f "${bin}" ] || fail_error "Node Mach-O binary not found: ${bin}"
			/bin/chmod u+w "${bin}"
			/usr/bin/xattr -c "${bin}" 2>/dev/null || true
			echo "==> Signing standalone Node Mach-O with JIT entitlements: ${bin}"
			codesign_leaf "${bin}" "com.vitruviansoftware.code.node" "${NODE_ENTITLEMENTS}"
			/usr/bin/codesign --verify --strict --verbose=2 "${bin}"
		done
	fi

	if [ "${DO_NOTARIZE}" -eq 1 ]; then
		local idx=0
		if [ "${#entitled_apps[@]}" -gt 0 ]; then
			for app in "${entitled_apps[@]}"; do
				idx=$((idx + 1))
				notarize_and_staple_app "${app}" "${idx}"
			done
		fi
		if [ "${#plain_apps[@]}" -gt 0 ]; then
			for app in "${plain_apps[@]}"; do
				idx=$((idx + 1))
				notarize_and_staple_app "${app}" "${idx}"
			done
		fi
		if [ "${#machos[@]}" -gt 0 ]; then
			for bin in "${machos[@]}"; do
				idx=$((idx + 1))
				local tool_zip="${WORK_DIR}/macho-${idx}.zip"
				/usr/bin/ditto -c -k "${bin}" "${tool_zip}"
				notarytool_submit_and_require_accepted "${tool_zip}" "$(/usr/bin/basename "${bin}")" "${bin}"
				/bin/rm -f "${tool_zip}"
			done
		fi
		if [ "${#node_machos[@]}" -gt 0 ]; then
			for bin in "${node_machos[@]}"; do
				idx=$((idx + 1))
				local node_zip="${WORK_DIR}/node-macho-${idx}.zip"
				/usr/bin/ditto -c -k "${bin}" "${node_zip}"
				notarytool_submit_and_require_accepted "${node_zip}" "$(/usr/bin/basename "${bin}")" "${bin}"
				/bin/rm -f "${node_zip}"
			done
		fi
	fi

	# Final verification on all signed (and, in release mode, stapled) bundles.
	if [ "${#entitled_apps[@]}" -gt 0 ]; then
		for app in "${entitled_apps[@]}"; do
			/usr/bin/codesign --verify --deep --strict --verbose=2 "${app}"
			if [ "${DO_NOTARIZE}" -eq 1 ]; then
				verify_app_gatekeeper "${app}"
			fi
		done
	fi
	if [ "${#plain_apps[@]}" -gt 0 ]; then
		for app in "${plain_apps[@]}"; do
			/usr/bin/codesign --verify --deep --strict --verbose=2 "${app}"
			if [ "${DO_NOTARIZE}" -eq 1 ]; then
				verify_app_gatekeeper "${app}"
			fi
		done
	fi
	if [ "${#machos[@]}" -gt 0 ]; then
		for bin in "${machos[@]}"; do
			/usr/bin/codesign --verify --strict --verbose=2 "${bin}"
		done
	fi
	if [ "${#node_machos[@]}" -gt 0 ]; then
		for bin in "${node_machos[@]}"; do
			/usr/bin/codesign --verify --strict --verbose=2 "${bin}"
		done
	fi

	if [ "${#GATEKEEPER_REJECTED[@]}" -gt 0 ]; then
		local rejected_list="" rejected
		for rejected in "${GATEKEEPER_REJECTED[@]}"; do
			rejected_list="${rejected_list:+${rejected_list}, }${rejected}"
		done
		fail_error "Gatekeeper rejected ${#GATEKEEPER_REJECTED[@]} app(s) after notarization: ${rejected_list}. See the Gatekeeper diagnostics groups above."
	fi
}

run_dmgs() {
	if [ "$#" -eq 0 ]; then
		usage_error
	fi

	local dmg
	for dmg in "$@"; do
		if [ ! -s "${dmg}" ]; then
			fail_error "DMG missing or empty: ${dmg}"
		fi
	done

	setup_credentials

	if [ "${SIGNING_MODE}" = "adhoc" ]; then
		for dmg in "$@"; do
			echo "==> SIGNING=adhoc: verified DMG exists (${dmg}); skipping Developer ID DMG signing and notarization."
		done
		return 0
	fi

	for dmg in "$@"; do
		/usr/bin/xattr -c "${dmg}" 2>/dev/null || true
		echo "==> Signing DMG with Developer ID: ${dmg}"
		/usr/bin/codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${dmg}"
		/usr/bin/codesign --verify --verbose=2 "${dmg}"
		if [ "${DO_NOTARIZE}" -eq 1 ]; then
			notarytool_submit_and_require_accepted "${dmg}" "$(/usr/bin/basename "${dmg}")"
			echo "==> Stapling notarization ticket to ${dmg}..."
			/usr/bin/xcrun stapler staple "${dmg}"
			/usr/bin/xcrun stapler validate "${dmg}"
			/usr/bin/codesign --verify --verbose=2 "${dmg}"
		fi
	done
}

main() {
	if [ "$#" -lt 1 ]; then
		usage_error
	fi
	local subcmd="$1"
	shift
	case "${subcmd}" in
	apps) run_apps "$@" ;;
	dmgs) run_dmgs "$@" ;;
	-h | --help)
		usage
		exit 0
		;;
	*) usage_error "Unknown subcommand '${subcmd}' (expected apps or dmgs)." ;;
	esac
}

main "$@"
