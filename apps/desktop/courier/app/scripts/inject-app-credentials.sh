#!/bin/bash
# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Puts Courier's own Telegram app ID into a Courier.app that is already built, and signs the app again.
#
# Telegram wants every app to register its own api_id and api_hash. Courier is sold to people who will never type
# them, so a packaged app carries Courier's: Contents/Resources/TelegramApp.plist, with api_id as an integer and
# api_hash as a string. The app reads it at launch (TelegramBuiltIn in CourierCore).
#
# This is done outside Bazel on purpose. A Bazel action's output can land in the remote cache, and the app ID must
# not. So Bazel builds an app with no keys in it, and this script adds them afterwards, on the Mac that packages.
#
# Usage: inject-app-credentials.sh [--allow-missing] [--entitlements FILE] <path/to/Courier.app>
#
# Where the values come from:
#   1. the environment: COURIER_TELEGRAM_API_ID and COURIER_TELEGRAM_API_HASH (both, or neither);
#   2. else the secret store (tools/sync-env-secrets/README.md): the files COURIER_TELEGRAM_API_ID and
#      COURIER_TELEGRAM_API_HASH in tools/sync-env-secrets/secrets/courier-release/. COURIER_SECRETS_DIR names
#      another folder to look in instead. A git worktree has no store of its own (it is gitignored), so the main
#      checkout's is used there.
#
# They are checked as the app and the engine check them: api_id a whole number from 1 to 2147483647, api_hash 32
# hexadecimal characters. The values are never printed, in an error or by `bash -x`.
#
# Signing, inside out, as the Vitruvian desktop app does it: the engine in Contents/Helpers first (with its own
# identifier, com.vitruviansoftware.courier.engine), then the app, with the entitlements in
# Resources/Courier.entitlements (--entitlements FILE names another file). No --deep. Extended attributes are
# stripped first, so nothing a download or a build left on a file spoils the seal.
#   - The identity is COURIER_SIGN_IDENTITY if it is set ("-" forces an ad hoc signature), else the first
#     "Developer ID Application" identity in the keychain, else ad hoc (CI has none).
#   - With an identity, both pieces get `--options runtime --timestamp` (the hardened runtime and Apple's
#     timestamp, which notarization needs). Every signature also gets --strip-disallowed-xattrs. A timestamp can fail on a bad network, so each is tried three times.
#     Ad hoc gets neither.
#   - Extra codesign flags can be passed in COURIER_SIGN_FLAGS (split on spaces, added to both signatures).
# What it used is printed ("Signed with Developer ID (team ...)" or "Signed ad hoc"); never anything secret.
# This is not a release: notarization and the DMG are milestone 6's.
#
# With no values the script says so, writes nothing and exits 1. --allow-missing skips the plist instead, so the
# app falls back to asking for keys, and still signs the app again. Exit 2 is for a mistake in how it was run or in
# a value.

# Nothing below may be traced: the values are in variables. (Reached after one traced line under `bash -x`.)
set +x
set -euo pipefail

allow_missing=0
app=""
entitlements="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../Resources/Courier.entitlements"
while [ "$#" -gt 0 ]; do
	case "$1" in
	--allow-missing) allow_missing=1 ;;
	--entitlements)
		if [ "$#" -lt 2 ]; then
			echo "inject-app-credentials: --entitlements needs a file" >&2
			exit 2
		fi
		entitlements="$2"
		shift
		;;
	-h | --help)
		sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2
		exit 2
		;;
	-*)
		echo "inject-app-credentials: unknown option $1" >&2
		exit 2
		;;
	*)
		if [ -n "$app" ]; then
			echo "inject-app-credentials: one Courier.app at a time" >&2
			exit 2
		fi
		app="$1"
		;;
	esac
	shift
done
if [ -z "$app" ]; then
	echo "Usage: inject-app-credentials.sh [--allow-missing] [--entitlements FILE] <path/to/Courier.app>" >&2
	exit 2
fi
if [ ! -d "$app/Contents" ]; then
	echo "inject-app-credentials: $app is not an app bundle (no Contents folder)" >&2
	exit 2
fi
app="$(cd "$app" && pwd)"
if [ ! -f "$entitlements" ]; then
	echo "inject-app-credentials: no entitlements file at $entitlements" >&2
	exit 2
fi
engine="$app/Contents/Helpers/courier-engine"
if [ ! -f "$engine" ]; then
	echo "inject-app-credentials: $app has no Contents/Helpers/courier-engine to sign" >&2
	exit 2
fi
engine_id="com.vitruviansoftware.courier.engine"

store_relative="tools/sync-env-secrets/secrets/courier-release"
id_name="COURIER_TELEGRAM_API_ID"
hash_name="COURIER_TELEGRAM_API_HASH"

# The folders to look for the store files in, most likely first. Under `bazel run` this script runs from the
# runfiles, which are not in any repository, so git is asked about BUILD_WORKSPACE_DIRECTORY (the checkout the
# command was run in) when that is set, else about the folder this script is in.
store_dirs() {
	if [ -n "${COURIER_SECRETS_DIR:-}" ]; then
		printf '%s\n' "$COURIER_SECRETS_DIR"
		return
	fi
	local base top common
	if [ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]; then
		base="$BUILD_WORKSPACE_DIRECTORY"
		printf '%s\n' "$base/$store_relative"
	else
		base="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	fi
	if top="$(git -C "$base" rev-parse --show-toplevel 2>/dev/null)"; then
		printf '%s\n' "$top/$store_relative"
	fi
	# In a worktree the store is in the main checkout: git's common folder is its .git.
	if common="$(git -C "$base" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
		printf '%s\n' "$(dirname "$common")/$store_relative"
	fi
}

# Reads the store file named $2 in folder $1 into the variable named $3, without spaces or line ends. Fails,
# silently, when there is no such file or it is empty.
read_store_file() {
	local dir="$1" name="$2" file
	file="$dir/$name"
	[ -f "$file" ] || return 1
	local value
	value="$(tr -d ' \t\r\n' <"$file")"
	[ -n "$value" ] || return 1
	printf -v "$3" '%s' "$value"
}

api_id=""
api_hash=""
origin=""
id_in_env="${COURIER_TELEGRAM_API_ID:-}"
hash_in_env="${COURIER_TELEGRAM_API_HASH:-}"
if [ -n "$id_in_env" ] && [ -n "$hash_in_env" ]; then
	api_id="$(printf '%s' "$id_in_env" | tr -d ' \t\r\n')"
	api_hash="$(printf '%s' "$hash_in_env" | tr -d ' \t\r\n')"
	origin="the environment"
elif [ -n "$id_in_env" ] || [ -n "$hash_in_env" ]; then
	echo "inject-app-credentials: only one of $id_name and $hash_name is set. Set both, or neither." >&2
	exit 2
else
	while IFS= read -r dir; do
		if read_store_file "$dir" "$id_name" api_id && read_store_file "$dir" "$hash_name" api_hash; then
			origin="the store ($dir)"
			break
		fi
		api_id=""
		api_hash=""
	done < <(store_dirs)
fi

if [ -z "$api_id" ] || [ -z "$api_hash" ]; then
	if [ "$allow_missing" -eq 1 ]; then
		echo "No Telegram app ID found (bazel run //tools/sync-env-secrets:bw-pull fetches it): leaving it out, so the app will ask for Telegram keys." >&2
	else
		{
			echo "No Telegram app ID found for Courier."
			echo "Looked for $id_name and $hash_name in the environment, then in the store:"
			store_dirs | while IFS= read -r dir; do echo "  $dir"; done
			echo "To fetch them: bazel run //tools/sync-env-secrets:bw-pull"
			echo "(apps/desktop/courier/app/README.md says how to add them.)"
		} >&2
		exit 1
	fi
else
	# Checked as the app and the engine check them. Only the rule is named in an error, never a value.
	if ! [[ "$api_id" =~ ^[0-9]+$ ]]; then
		echo "inject-app-credentials: api_id (from $origin) is not a whole number." >&2
		exit 2
	fi
	stripped="${api_id#"${api_id%%[!0]*}"}"
	if [ -z "$stripped" ] || [ "${#stripped}" -gt 10 ] || [ "$stripped" -gt 2147483647 ]; then
		echo "inject-app-credentials: api_id (from $origin) must be from 1 to 2147483647." >&2
		exit 2
	fi
	api_id="$stripped"
	hex32='^[0-9a-fA-F]{32}$'
	if ! [[ "$api_hash" =~ $hex32 ]]; then
		echo "inject-app-credentials: api_hash (from $origin) must be 32 hexadecimal characters." >&2
		exit 2
	fi

	resources="$app/Contents/Resources"
	mkdir -p "$resources"
	target="$resources/TelegramApp.plist"
	# Written by the shell, not passed to a tool, so the values are never in a process's arguments. Both are
	# digits or hex digits, so nothing needs escaping in the XML.
	staged="$(umask 077 && mktemp "$resources/.TelegramApp.XXXXXX")"
	trap 'rm -f "$staged"' EXIT
	{
		echo '<?xml version="1.0" encoding="UTF-8"?>'
		echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
		echo '<plist version="1.0">'
		echo '<dict>'
		echo '	<key>api_id</key>'
		echo "	<integer>$api_id</integer>"
		echo '	<key>api_hash</key>'
		echo "	<string>$api_hash</string>"
		echo '</dict>'
		echo '</plist>'
	} >"$staged"
	chmod 644 "$staged"
	if ! plutil -lint "$staged" >/dev/null 2>&1; then
		echo "inject-app-credentials: the property list it wrote did not check out." >&2
		exit 2
	fi
	mv -f "$staged" "$target"
	trap - EXIT
	echo "Wrote Contents/Resources/TelegramApp.plist from $origin."
fi

# The plist is part of the app's seal, so the app is signed again whether or not one was written.
#
# The identity: COURIER_SIGN_IDENTITY, else the first Developer ID Application one in the keychain (by its
# hash, so two certificates of the same name cannot be confused), else ad hoc.
identity="${COURIER_SIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
	# One hash, even when the same certificate is listed twice (it is, when it is in two keychains).
	identity="$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Developer ID Application/ && !seen[$2]++ { print $2; exit }' || true)"
	identity="${identity:--}"
fi
# Extra flags from the environment, split on spaces. (`${flags[@]+...}`: an empty array is an unset variable to
# bash 3.2's `set -u`.)
extra_flags=()
if [ -n "${COURIER_SIGN_FLAGS:-}" ]; then
	read -r -a extra_flags <<<"$COURIER_SIGN_FLAGS"
fi
# --strip-disallowed-xattrs: an attribute that cannot go in a seal (a download's quarantine, Finder info) is dropped
# rather than failing the signing or, later, notarization.
id_flags=(--strip-disallowed-xattrs)
if [ "$identity" != "-" ]; then
	id_flags+=(--options runtime --timestamp)
fi

# codesign, with the arguments given. A timestamp comes from Apple's server and can fail on a bad network, so a
# signature that asks for one is tried up to three times, as the Vitruvian build does.
sign_one() {
	local attempt
	for attempt in 1 2 3; do
		if codesign "$@" >/dev/null; then
			return 0
		fi
		if [ "$identity" = "-" ] || [ "$attempt" -eq 3 ]; then
			return 1
		fi
		echo "  Signing failed; trying again ($((attempt + 1))/3)" >&2
		sleep "$attempt"
	done
}

# Anything a download or a build left on a file (quarantine, Finder info) would fail the seal; Bazel's outputs
# are read-only, which would fail the write.
chmod -R u+w "$app"
# (macOS xattr has no -r: find walks the bundle.)
find "$app" -exec xattr -c {} + 2>/dev/null || true

sign_one --force "${id_flags[@]+"${id_flags[@]}"}" --identifier "$engine_id" ${extra_flags[@]+"${extra_flags[@]}"} \
	--sign "$identity" "$engine" || {
	echo "inject-app-credentials: codesign could not sign the engine in $app." >&2
	exit 1
}
sign_one --force "${id_flags[@]+"${id_flags[@]}"}" --entitlements "$entitlements" ${extra_flags[@]+"${extra_flags[@]}"} \
	--sign "$identity" "$app" || {
	echo "inject-app-credentials: codesign could not sign $app." >&2
	exit 1
}
codesign --verify --deep --strict "$app" || {
	echo "inject-app-credentials: $app does not pass codesign --verify after signing." >&2
	exit 1
}

# Say which kind of signature it got, from what codesign reports about the result.
details="$(codesign -dv --verbose=2 "$app" 2>&1 || true)"
team="$(printf '%s\n' "$details" | sed -n 's/^TeamIdentifier=//p' | head -1)"
if [ "$identity" = "-" ]; then
	echo "Signed $app ad hoc."
elif printf '%s\n' "$details" | grep -q '^Authority=Developer ID Application'; then
	echo "Signed $app with Developer ID (team ${team:-unknown})."
else
	echo "Signed $app with a certificate that is not a Developer ID (team ${team:--})."
fi
