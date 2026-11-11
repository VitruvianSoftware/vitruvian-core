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

# Signs, notarizes, staples, and verifies Vitruvian Code's macOS release bundles
# (`Vitruvian Code.app`, the migration bridge `NexusAgent.app`, the standalone
# `vitruvian-code-tool` Mach-O, and the `.dmg` disk images).
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
#                           rehearsal workflow (.github/workflows/nexus-agent-mirror-toolchain.yaml).

set -euo pipefail
set +x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_ENTITLEMENTS="${VITRUVIAN_CODE_ENTITLEMENTS:-${REPO_ROOT}/macos/Resources/VitruvianCode.entitlements}"

SIGNING_MODE="${SIGNING:-developer-id}"
WORK_DIR=""
TMP_KEYCHAIN=""
NOTARY_KEY_FILE=""
KEYCHAIN_RESTORE_NEEDED=""
ORIG_KEYCHAINS=()
SIGN_IDENTITY=""
DO_NOTARIZE=0

cleanup() {
	local rc=$?
	set +e
	if [ -n "${KEYCHAIN_RESTORE_NEEDED}" ]; then
		if [ "${#ORIG_KEYCHAINS[@]}" -gt 0 ]; then
			security list-keychains -d user -s "${ORIG_KEYCHAINS[@]}" >/dev/null 2>&1 || true
		fi
	fi
	if [ -n "${TMP_KEYCHAIN}" ]; then
		security delete-keychain "${TMP_KEYCHAIN}" >/dev/null 2>&1 || true
	fi
	if [ -n "${WORK_DIR}" ] && [ -d "${WORK_DIR}" ]; then
		rm -rf "${WORK_DIR}"
	fi
	exit "${rc}"
}
trap cleanup EXIT INT TERM

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
	cleaned="$(printf '%s' "${raw}" | tr -d ' \r\n\t')"
	(
		umask 077
		if printf '%s' "${cleaned}" | base64 --decode >"${dest}" 2>/dev/null; then
			:
		elif printf '%s' "${cleaned}" | base64 -D >"${dest}" 2>/dev/null; then
			:
		else
			exit 1
		fi
	) || fail_error "Failed to base64-decode credential into temporary file $(basename "${dest}")."
	chmod 600 "${dest}"
}

write_notary_key() {
	local raw="$1"
	local dest="$2"
	if printf '%s' "${raw}" | grep -q -- "-----BEGIN"; then
		(
			umask 077
			printf '%s\n' "${raw}" >"${dest}"
		)
		chmod 600 "${dest}"
	else
		decode_base64_to_file "${raw}" "${dest}"
	fi
	if ! grep -q -- "-----BEGIN" "${dest}"; then
		fail_error "VITRUVIAN_NOTARY_API_KEY_P8 did not decode to a PEM private key."
	fi
}

setup_credentials() {
	WORK_DIR="$(mktemp -d "${RUNNER_TEMP:-/tmp}/vc-signing.XXXXXX")"
	chmod 700 "${WORK_DIR}"

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
			kc_trimmed="$(printf '%s' "${kc_line}" | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')"
			if [ -n "${kc_trimmed}" ]; then
				ORIG_KEYCHAINS+=("${kc_trimmed}")
			fi
		done < <(security list-keychains -d user)

		local p12_file="${WORK_DIR}/signing.p12"
		decode_base64_to_file "${VITRUVIAN_SIGNING_CERT_P12}" "${p12_file}"

		local kc_pass
		kc_pass="$(LC_ALL=C head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)"
		TMP_KEYCHAIN="${WORK_DIR}/vitruvian-code-signing.keychain-db"

		security create-keychain -p "${kc_pass}" "${TMP_KEYCHAIN}"
		chmod 600 "${TMP_KEYCHAIN}"
		security set-keychain-settings -lut 21600 "${TMP_KEYCHAIN}"
		security unlock-keychain -p "${kc_pass}" "${TMP_KEYCHAIN}"
		security import "${p12_file}" \
			-k "${TMP_KEYCHAIN}" \
			-P "${VITRUVIAN_SIGNING_CERT_PASSWORD}" \
			-T /usr/bin/codesign \
			-T /usr/bin/security >/dev/null
		rm -f "${p12_file}"

		security set-key-partition-list \
			-S apple-tool:,apple:,codesign: \
			-s -k "${kc_pass}" "${TMP_KEYCHAIN}" >/dev/null

		KEYCHAIN_RESTORE_NEEDED=1
		if [ "${#ORIG_KEYCHAINS[@]}" -gt 0 ]; then
			security list-keychains -d user -s "${TMP_KEYCHAIN}" "${ORIG_KEYCHAINS[@]}"
		else
			security list-keychains -d user -s "${TMP_KEYCHAIN}"
		fi

		local listing
		listing="$(security find-identity -v -p codesigning "${TMP_KEYCHAIN}")"
		SIGN_IDENTITY="$(printf '%s\n' "${listing}" | awk '/Developer ID Application:/ { print $2; exit }')"
		local identity_label
		identity_label="$(printf '%s\n' "${listing}" | grep 'Developer ID Application:' | head -1 | sed -E 's/.*"(.*)".*/\1/' || true)"
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
		listing="$(security find-identity -v -p codesigning)"
		SIGN_IDENTITY="$(printf '%s\n' "${listing}" | awk '/Developer ID Application:/ { print $2; exit }')"
		local identity_label
		identity_label="$(printf '%s\n' "${listing}" | grep 'Developer ID Application:' | head -1 | sed -E 's/.*"(.*)".*/\1/' || true)"
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
	local id_args=()
	if [ -n "${identifier}" ]; then
		id_args=(--identifier "${identifier}")
	fi
	if [ "${SIGNING_MODE}" = "adhoc" ]; then
		if [ "${#id_args[@]}" -gt 0 ]; then
			codesign --force "${id_args[@]}" --sign - "${target}"
		else
			codesign --force --sign - "${target}"
		fi
	else
		if [ "${#id_args[@]}" -gt 0 ]; then
			codesign --force --options runtime --timestamp "${id_args[@]}" --sign "${SIGN_IDENTITY}" "${target}"
		else
			codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" "${target}"
		fi
	fi
}

clear_xattrs() {
	local target="$1"
	find "${target}" -print0 | xargs -0 xattr -c -s 2>/dev/null || true
}

sign_app_inside_out() {
	local app="$1"
	local entitlements="${2:-}"

	if [ ! -d "${app}" ]; then
		fail_error "App bundle not found: ${app}"
	fi
	if [ -n "${entitlements}" ] && [ ! -f "${entitlements}" ]; then
		fail_error "Entitlements file not found: ${entitlements}"
	fi

	chmod -R u+w "${app}"
	clear_xattrs "${app}"

	# 1. Sign nested regular Mach-O files (helpers, dylibs) inside-out, excluding
	#    the bundle's own Contents/MacOS/* main executable(s) which are signed by
	#    the bundle pass below.
	while IFS= read -r candidate; do
		[ -n "${candidate}" ] || continue
		case "${candidate}" in
		"${app}/Contents/MacOS/"*) continue ;;
		esac
		if file -b "${candidate}" | grep -q "Mach-O"; then
			echo "    Signing nested Mach-O: ${candidate}"
			codesign_leaf "${candidate}"
		fi
	done < <(find "${app}/Contents" -depth -type f)

	# 2. Sign nested frameworks, XPC services, or helper app bundles inside-out.
	while IFS= read -r nested_bundle; do
		[ -n "${nested_bundle}" ] || continue
		echo "    Signing nested bundle: ${nested_bundle}"
		codesign_leaf "${nested_bundle}"
	done < <(find "${app}/Contents" -depth -type d \( -name '*.framework' -o -name '*.xpc' -o -name '*.app' \))

	# 3. Sign the top-level .app bundle.
	echo "==> Signing app bundle: ${app}"
	if [ "${SIGNING_MODE}" = "adhoc" ]; then
		if [ -n "${entitlements}" ]; then
			codesign --force --entitlements "${entitlements}" --sign - "${app}"
		else
			codesign --force --sign - "${app}"
		fi
	else
		if [ -n "${entitlements}" ]; then
			codesign --force --options runtime --timestamp --entitlements "${entitlements}" --sign "${SIGN_IDENTITY}" "${app}"
		else
			codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" "${app}"
		fi
	fi

	codesign --verify --deep --strict --verbose=2 "${app}"
}

notarytool_submit_and_require_accepted() {
	local submit_path="$1"
	local label="$2"
	local out_file="${WORK_DIR}/notary-$(date +%s)-$$.log"

	echo "==> Submitting ${label} to Apple notary service..."
	local rc=0
	xcrun notarytool submit "${submit_path}" \
		--key "${NOTARY_KEY_FILE}" \
		--key-id "${VITRUVIAN_NOTARY_KEY_ID}" \
		--issuer "${VITRUVIAN_NOTARY_ISSUER_ID}" \
		--wait 2>&1 | tee "${out_file}" || rc=$?

	local sub_id
	sub_id="$(awk '/id:/ { print $2; exit }' "${out_file}" || true)"

	if [ "${rc}" -ne 0 ] || ! grep -q "status: Accepted" "${out_file}"; then
		if [ -n "${sub_id}" ]; then
			echo "==> Fetching Apple notary log for submission ${sub_id}:" >&2
			xcrun notarytool log "${sub_id}" \
				--key "${NOTARY_KEY_FILE}" \
				--key-id "${VITRUVIAN_NOTARY_KEY_ID}" \
				--issuer "${VITRUVIAN_NOTARY_ISSUER_ID}" >&2 || true
		fi
		rm -f "${out_file}"
		fail_error "Notarization failed for ${label}."
	fi
	rm -f "${out_file}"
}

notarize_and_staple_app() {
	local app="$1"
	local idx="$2"
	local base
	base="$(basename "${app}")"
	local zip_path="${WORK_DIR}/app-${idx}.zip"

	clear_xattrs "${app}"
	codesign --verify --deep --strict "${app}"
	/usr/bin/ditto -c -k --keepParent "${app}" "${zip_path}"
	notarytool_submit_and_require_accepted "${zip_path}" "${base}"
	rm -f "${zip_path}"

	echo "==> Stapling notarization ticket to ${app}..."
	xcrun stapler staple "${app}"
	xcrun stapler validate "${app}"
}

run_apps() {
	local entitled_apps=()
	local plain_apps=()
	local machos=()

	if [ "$#" -eq 0 ]; then
		entitled_apps=(
			"/tmp/dist-universal/Vitruvian Code.app"
			"/tmp/dist-arm64/Vitruvian Code.app"
			"/tmp/dist-x86_64/Vitruvian Code.app"
		)
		plain_apps=(
			"/tmp/dist-bridge/NexusAgent.app"
		)
		machos=(
			"/tmp/universal/vitruvian-code-tool"
		)
	else
		while [ "$#" -gt 0 ]; do
			case "$1" in
			--entitlements-app)
				[ "$#" -ge 2 ] || fail_error "--entitlements-app requires a path"
				entitled_apps+=("$2")
				shift 2
				;;
			--plain-app)
				[ "$#" -ge 2 ] || fail_error "--plain-app requires a path"
				plain_apps+=("$2")
				shift 2
				;;
			--macho)
				[ "$#" -ge 2 ] || fail_error "--macho requires a path"
				machos+=("$2")
				shift 2
				;;
			*)
				fail_error "Unknown apps argument: $1"
				;;
			esac
		done
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
			chmod u+w "${bin}"
			xattr -c "${bin}" 2>/dev/null || true
			echo "==> Signing standalone Mach-O: ${bin}"
			codesign_leaf "${bin}" "com.vitruviansoftware.code.tool"
			codesign --verify --strict --verbose=2 "${bin}"
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
				notarytool_submit_and_require_accepted "${tool_zip}" "$(basename "${bin}")"
				rm -f "${tool_zip}"
			done
		fi
	fi

	# Final verification on all signed (and, in release mode, stapled) bundles.
	if [ "${#entitled_apps[@]}" -gt 0 ]; then
		for app in "${entitled_apps[@]}"; do
			codesign --verify --deep --strict --verbose=2 "${app}"
			if [ "${DO_NOTARIZE}" -eq 1 ]; then
				spctl -a -vv -t exec "${app}"
			fi
		done
	fi
	if [ "${#plain_apps[@]}" -gt 0 ]; then
		for app in "${plain_apps[@]}"; do
			codesign --verify --deep --strict --verbose=2 "${app}"
			if [ "${DO_NOTARIZE}" -eq 1 ]; then
				spctl -a -vv -t exec "${app}"
			fi
		done
	fi
	if [ "${#machos[@]}" -gt 0 ]; then
		for bin in "${machos[@]}"; do
			codesign --verify --strict --verbose=2 "${bin}"
		done
	fi
}

run_dmgs() {
	if [ "$#" -eq 0 ]; then
		fail_error "Usage: sign-and-notarize.sh dmgs <dmg>..."
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
		xattr -c "${dmg}" 2>/dev/null || true
		echo "==> Signing DMG with Developer ID: ${dmg}"
		codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${dmg}"
		codesign --verify --verbose=2 "${dmg}"
		if [ "${DO_NOTARIZE}" -eq 1 ]; then
			notarytool_submit_and_require_accepted "${dmg}" "$(basename "${dmg}")"
			echo "==> Stapling notarization ticket to ${dmg}..."
			xcrun stapler staple "${dmg}"
			xcrun stapler validate "${dmg}"
			codesign --verify --verbose=2 "${dmg}"
		fi
	done
}

main() {
	if [ "$#" -lt 1 ]; then
		fail_error "Usage: sign-and-notarize.sh <apps|dmgs> [args...]"
	fi
	local subcmd="$1"
	shift
	case "${subcmd}" in
	apps) run_apps "$@" ;;
	dmgs) run_dmgs "$@" ;;
	*) fail_error "Unknown subcommand '${subcmd}' (expected apps or dmgs)." ;;
	esac
}

main "$@"
