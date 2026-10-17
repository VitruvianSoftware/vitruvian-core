#!/bin/bash
# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# inject-app-credentials.sh, against a tiny stand-in .app:
#   - it writes a valid TelegramApp.plist (api_id an integer, api_hash a string) from the environment, or from
#     the store folder, and the environment wins;
#   - it signs the app again, so the app passes `codesign --verify --deep --strict` with the plist in it;
#   - it refuses values that don't fit, writes nothing, and never prints a value (not even under `bash -x`);
#   - with no values it says so and exits 1, or with --allow-missing skips the plist and still signs.
# Every value here is made up.
#
# Usage: inject_app_credentials_test.sh <inject-app-credentials.sh>
set -euo pipefail

injector="${1:?Usage: inject_app_credentials_test.sh <inject-app-credentials.sh>}"
case "$injector" in /*) ;; *) injector="$PWD/$injector" ;; esac
work="${TEST_TMPDIR:-$(mktemp -d)}/inject"
rm -rf "$work"
mkdir -p "$work"

# Nothing from the machine running the test may reach the script.
unset COURIER_TELEGRAM_API_ID COURIER_TELEGRAM_API_HASH COURIER_SIGN_IDENTITY BUILD_WORKSPACE_DIRECTORY

failed=0
fail() {
	echo "FAIL: $*" >&2
	failed=1
}
ok() { echo "ok: $*"; }

good_id=4242424
good_hash=0123456789abcdef0123456789abcdef
other_id=7070707
other_hash=fedcba9876543210fedcba9876543210

# A fresh, signed stand-in app: a real executable, so codesign has something to seal.
new_app() {
	local app="$work/apps/$1/Courier.app"
	rm -rf "$work/apps/$1"
	mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
	cp /usr/bin/true "$app/Contents/MacOS/Dummy"
	cat >"$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Dummy</string>
<key>CFBundleIdentifier</key><string>test.courier.dummy</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
	codesign --force --deep --sign - "$app" >/dev/null 2>&1
	echo "$app"
}

verifies() { codesign --verify --deep --strict "$1" >/dev/null 2>&1; }

# No value may appear in what the script printed.
leaks() {
	local output="$1" value
	shift
	for value in "$@"; do
		if grep -qF -- "$value" "$output"; then
			return 0
		fi
	done
	return 1
}

empty_store="$work/empty-store"
mkdir -p "$empty_store"

# --- 1. From the environment: a valid plist, a valid signature, nothing printed.
app="$(new_app env)"
out="$work/env.out"
if COURIER_SECRETS_DIR="$empty_store" COURIER_TELEGRAM_API_ID="$good_id" COURIER_TELEGRAM_API_HASH="$good_hash" \
	"$injector" "$app" >"$out" 2>&1; then
	ok "injects from the environment"
else
	fail "injecting from the environment failed: $(cat "$out")"
fi
plist="$app/Contents/Resources/TelegramApp.plist"
if [ -f "$plist" ] && plutil -lint "$plist" >/dev/null 2>&1; then
	ok "TelegramApp.plist is there and well formed"
else
	fail "TelegramApp.plist is missing or malformed"
fi
[ "$(plutil -type api_id "$plist" 2>/dev/null)" = "integer" ] && ok "api_id is an integer" || fail "api_id is not an integer"
[ "$(plutil -type api_hash "$plist" 2>/dev/null)" = "string" ] && ok "api_hash is a string" || fail "api_hash is not a string"
[ "$(plutil -extract api_id raw -o - "$plist" 2>/dev/null)" = "$good_id" ] && ok "api_id is the one given" || fail "api_id differs"
[ "$(plutil -extract api_hash raw -o - "$plist" 2>/dev/null)" = "$good_hash" ] && ok "api_hash is the one given" || fail "api_hash differs"
if verifies "$app"; then ok "the app passes codesign --verify --deep --strict"; else fail "the app does not verify after injection"; fi
if leaks "$out" "$good_id" "$good_hash"; then fail "the script printed a value: $(cat "$out")"; else ok "nothing printed a value"; fi
ls "$app/Contents/Resources" | grep -q '^\.TelegramApp\.' && fail "a staging file was left behind" || ok "no staging file left behind"

# The signature covers the plist: change it and the app no longer verifies. (So the signing was done after.)
cp "$plist" "$work/plist.bak"
printf '\n' >>"$plist"
if verifies "$app"; then fail "a changed plist still verifies: the seal does not cover it"; else ok "the seal covers the plist"; fi
cp "$work/plist.bak" "$plist"

# --- 2. Run again with other values: replaced, still valid.
if COURIER_SECRETS_DIR="$empty_store" COURIER_TELEGRAM_API_ID="$other_id" COURIER_TELEGRAM_API_HASH="$other_hash" \
	"$injector" "$app" >/dev/null 2>&1 &&
	[ "$(plutil -extract api_id raw -o - "$plist")" = "$other_id" ] && verifies "$app"; then
	ok "a second run replaces the plist and signs again"
else
	fail "a second run did not replace the plist"
fi

# --- 3. From the store; the environment wins when both are there.
store="$work/store"
mkdir -p "$store"
printf '%s\n' "$other_id" >"$store/COURIER_TELEGRAM_API_ID"
printf '  %s  \n' "$other_hash" >"$store/COURIER_TELEGRAM_API_HASH"
app="$(new_app store)"
if COURIER_SECRETS_DIR="$store" "$injector" "$app" >"$work/store.out" 2>&1 &&
	[ "$(plutil -extract api_id raw -o - "$app/Contents/Resources/TelegramApp.plist")" = "$other_id" ] &&
	[ "$(plutil -extract api_hash raw -o - "$app/Contents/Resources/TelegramApp.plist")" = "$other_hash" ] &&
	verifies "$app"; then
	ok "injects from the store files (spaces and line ends ignored)"
else
	fail "injecting from the store failed: $(cat "$work/store.out")"
fi
if leaks "$work/store.out" "$other_id" "$other_hash"; then fail "the store run printed a value"; else ok "the store run printed no value"; fi
app="$(new_app both)"
COURIER_SECRETS_DIR="$store" COURIER_TELEGRAM_API_ID="$good_id" COURIER_TELEGRAM_API_HASH="$good_hash" \
	"$injector" "$app" >/dev/null 2>&1 || true
[ "$(plutil -extract api_id raw -o - "$app/Contents/Resources/TelegramApp.plist" 2>/dev/null)" = "$good_id" ] &&
	ok "the environment wins over the store" || fail "the store won over the environment"

# --- 4. Values that don't fit: refused, nothing written, nothing echoed, the app left as it was.
refuses() {
	local name="$1" id="$2" hash="$3" app status out
	app="$(new_app "refuse-$name")"
	out="$work/refuse-$name.out"
	set +e
	COURIER_SECRETS_DIR="$empty_store" COURIER_TELEGRAM_API_ID="$id" COURIER_TELEGRAM_API_HASH="$hash" \
		"$injector" "$app" >"$out" 2>&1
	status=$?
	set -e
	if [ "$status" -ne 0 ]; then ok "refuses $name (exit $status)"; else fail "accepted $name"; fi
	if [ -e "$app/Contents/Resources/TelegramApp.plist" ]; then fail "wrote a plist for $name"; fi
	if leaks "$out" "$id" "$hash"; then fail "the error for $name echoed a value: $(cat "$out")"; fi
	if ! verifies "$app"; then fail "the app was changed by a refused run ($name)"; fi
}
refuses "a word for the id" "notanumber" "$good_hash"
refuses "a zero id" "0" "$good_hash"
refuses "an id over 2^31-1" "2147483648" "$good_hash"
refuses "a huge id" "99999999999999999999999" "$good_hash"
refuses "a negative id" "-4242424" "$good_hash"
refuses "a short hash" "$good_id" "0123456789abcdef"
refuses "a long hash" "$good_id" "${good_hash}00"
refuses "a hash that is not hex" "$good_id" "ghijklmnopqrstuvwxyzghijklmnopqr"
# One of the two only.
app="$(new_app half)"
set +e
COURIER_SECRETS_DIR="$store" COURIER_TELEGRAM_API_ID="$good_id" "$injector" "$app" >"$work/half.out" 2>&1
status=$?
set -e
if [ "$status" -ne 0 ] && [ ! -e "$app/Contents/Resources/TelegramApp.plist" ] && ! leaks "$work/half.out" "$good_id"; then
	ok "refuses an id without a hash"
else
	fail "an id without a hash was not refused cleanly (exit $status)"
fi

# --- 5. `bash -x` shows nothing: the values are not in a trace.
app="$(new_app trace)"
COURIER_SECRETS_DIR="$empty_store" COURIER_TELEGRAM_API_ID="$good_id" COURIER_TELEGRAM_API_HASH="$good_hash" \
	bash -x "$injector" "$app" >"$work/trace.out" 2>&1 || true
if leaks "$work/trace.out" "$good_id" "$good_hash"; then fail "a value showed under bash -x"; else ok "nothing printed under bash -x"; fi
if [ -f "$app/Contents/Resources/TelegramApp.plist" ]; then ok "and it still injected under bash -x"; else fail "no plist under bash -x"; fi

# --- 6. Nothing to inject: says so plainly (store path and bw-pull), writes nothing, exits non-zero.
app="$(new_app missing)"
set +e
COURIER_SECRETS_DIR="$empty_store" "$injector" "$app" >"$work/missing.out" 2>&1
status=$?
set -e
[ "$status" -eq 1 ] && ok "no values: exit 1" || fail "no values: exit $status, not 1"
grep -q "$empty_store" "$work/missing.out" && ok "it names the store it looked in" || fail "it does not name the store"
grep -q "bw-pull" "$work/missing.out" && ok "it names the bw-pull command" || fail "it does not name bw-pull"
[ ! -e "$app/Contents/Resources/TelegramApp.plist" ] && ok "no plist written" || fail "a plist was written"

# --- 7. --allow-missing: no plist, still signed, exit 0.
app="$(new_app allow)"
if COURIER_SECRETS_DIR="$empty_store" "$injector" --allow-missing "$app" >"$work/allow.out" 2>&1; then
	ok "--allow-missing exits 0"
else
	fail "--allow-missing failed: $(cat "$work/allow.out")"
fi
[ ! -e "$app/Contents/Resources/TelegramApp.plist" ] && ok "--allow-missing writes no plist" || fail "--allow-missing wrote a plist"
verifies "$app" && ok "--allow-missing leaves a verifying app" || fail "--allow-missing left an app that does not verify"
# ...and with values present it still injects.
app="$(new_app allow-present)"
COURIER_SECRETS_DIR="$store" "$injector" --allow-missing "$app" >/dev/null 2>&1 || true
[ -f "$app/Contents/Resources/TelegramApp.plist" ] && ok "--allow-missing still injects when it can" || fail "--allow-missing skipped values that were there"

# --- 8. Mistakes in how it is run.
set +e
"$injector" >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "no argument is a usage error" || fail "no argument was not a usage error"
"$injector" "$work/not-an-app" >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "a folder that is not an app is a usage error" || fail "a missing app was not a usage error"
set -e

exit "$failed"
