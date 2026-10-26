#!/bin/bash
# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# inject-app-credentials.sh, against a tiny stand-in .app:
#   - it writes a valid TelegramApp.plist (api_id an integer, api_hash a string) from the environment, or from
#     the store folder, and the environment wins;
#   - it signs the app again, so the app passes `codesign --verify --deep --strict` with the plist in it;
#   - it refuses values that don't fit, writes nothing, and never prints a value (not even under `bash -x`);
#   - with no values it says so and exits 1, or with --allow-missing skips the plist and still signs;
#   - it signs inside out (the engine, then the app) with the hardened runtime and a timestamp when there is an
#     identity, and with neither ad hoc; a fake codesign on the PATH records how it was called.
# Every value here is made up.
#
# Usage: inject_app_credentials_test.sh <inject-app-credentials.sh> [<Courier.entitlements>]
set -euo pipefail

injector="${1:?Usage: inject_app_credentials_test.sh <inject-app-credentials.sh> [<Courier.entitlements>]}"
case "$injector" in /*) ;; *) injector="$PWD/$injector" ;; esac
real_entitlements="${2:-}"
if [ -n "$real_entitlements" ]; then
	case "$real_entitlements" in /*) ;; *) real_entitlements="$PWD/$real_entitlements" ;; esac
fi
work="${TEST_TMPDIR:-$(mktemp -d)}/inject"
rm -rf "$work"
mkdir -p "$work"

# Nothing from the machine running the test may reach the script.
unset COURIER_TELEGRAM_API_ID COURIER_TELEGRAM_API_HASH COURIER_SIGN_IDENTITY COURIER_SIGN_FLAGS \
	BUILD_WORKSPACE_DIRECTORY COURIER_SECRETS_DIR

# This Mac may have a Developer ID in its keychain; the real-codesign cases below want the ad hoc path, so a
# `security` that finds no identity is first on the PATH. (The fake-codesign cases at the end swap in their own.)
no_identity_bin="$work/bin-no-identity"
mkdir -p "$no_identity_bin"
cat >"$no_identity_bin/security" <<'FAKE'
#!/bin/sh
echo "     0 valid identities found"
FAKE
chmod 755 "$no_identity_bin/security"
export PATH="$no_identity_bin:$PATH"

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

# A fresh, signed stand-in app: a real executable, and a stand-in engine, so codesign has something to seal.
new_app() {
	local app="$work/apps/$1/Courier.app"
	rm -rf "$work/apps/$1"
	mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Helpers"
	cp /usr/bin/true "$app/Contents/MacOS/Dummy"
	cp /usr/bin/true "$app/Contents/Helpers/courier-engine"
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

# An entitlements file of the test's own, for runs where the injector is not beside Resources/.
ents="$work/Courier.entitlements"
cat >"$ents" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict></dict></plist>
PLIST

empty_store="$work/empty-store"
mkdir -p "$empty_store"

# --- 1. From the environment: a valid plist, a valid signature, nothing printed.
app="$(new_app env)"
# The engine changes after the app was signed (as the engine does when Bazel builds it): the app no longer
# verifies, and only signing the whole bundle again, nested engine included, puts that right.
cp /usr/bin/false "$app/Contents/Helpers/courier-engine"
if verifies "$app"; then fail "the stand-in app still verifies after its engine changed"; fi
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
if codesign --verify --strict "$app/Contents/Helpers/courier-engine" >/dev/null 2>&1; then
	ok "the engine was signed again with the app"
else
	fail "the engine was not signed again"
fi
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

# --- 8. Extra codesign flags from COURIER_SIGN_FLAGS reach codesign.
app="$(new_app flags)"
COURIER_SECRETS_DIR="$store" COURIER_SIGN_FLAGS="--options runtime" "$injector" "$app" >"$work/flags.out" 2>&1 || true
details="$(codesign -d --verbose=2 "$app" 2>&1 || true)"
if [[ "$details" == *runtime* ]] && verifies "$app"; then
	ok "COURIER_SIGN_FLAGS reaches codesign"
else
	fail "COURIER_SIGN_FLAGS did not reach codesign: $(cat "$work/flags.out")"
fi

# --- 9. Under `bazel run` the script is in the runfiles, which are not in any repository, and the store is in
# the main checkout while the command was run in a worktree: BUILD_WORKSPACE_DIRECTORY leads git to it.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
main="$work/main-checkout"
rm -rf "$main" "$work/worktree" "$work/runfiles"
mkdir -p "$main" "$work/runfiles"
git -C "$main" init -q
git -C "$main" -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m init
git -C "$main" worktree add -q "$work/worktree" -b scratch
mkdir -p "$main/tools/sync-env-secrets/secrets/courier-release"
printf '%s' "$other_id" >"$main/tools/sync-env-secrets/secrets/courier-release/COURIER_TELEGRAM_API_ID"
printf '%s' "$other_hash" >"$main/tools/sync-env-secrets/secrets/courier-release/COURIER_TELEGRAM_API_HASH"
cp "$injector" "$work/runfiles/inject-app-credentials.sh"
app="$(new_app worktree)"
if BUILD_WORKSPACE_DIRECTORY="$work/worktree" "$work/runfiles/inject-app-credentials.sh" --entitlements "$ents" "$app" >"$work/worktree.out" 2>&1 &&
	[ "$(plutil -extract api_id raw -o - "$app/Contents/Resources/TelegramApp.plist")" = "$other_id" ] && verifies "$app"; then
	ok "finds the main checkout's store from a worktree, outside any repository"
else
	fail "did not find the main checkout's store from a worktree: $(cat "$work/worktree.out")"
fi
if leaks "$work/worktree.out" "$other_id" "$other_hash"; then fail "the worktree run printed a value"; fi
# Nothing in either place: still the plain missing-values answer.
rm -f "$main/tools/sync-env-secrets/secrets/courier-release/"*
app="$(new_app worktree-empty)"
set +e
BUILD_WORKSPACE_DIRECTORY="$work/worktree" "$work/runfiles/inject-app-credentials.sh" --entitlements "$ents" "$app" >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 1 ] && ok "an empty main checkout store is exit 1" || fail "an empty store gave exit $status"

# --- 10. Mistakes in how it is run.
set +e
"$injector" >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "no argument is a usage error" || fail "no argument was not a usage error"
"$injector" "$work/not-an-app" >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "a folder that is not an app is a usage error" || fail "a missing app was not a usage error"
set -e

# --- 11. How it signs, seen through a fake codesign that records every call. (The real codesign is used
# above; here only the arguments matter.)
fake_cs="$work/bin-fake-codesign"
fake_devid="$work/bin-devid"
mkdir -p "$fake_cs" "$fake_devid"
cat >"$fake_cs/codesign" <<'FAKE'
#!/bin/bash
# Records its arguments, one call a line, joined with "|". FAKE_FAIL_FIRST=N makes the first N signings fail.
printf '%s\n' "$(IFS='|'; echo "$*")" >>"$FAKE_CODESIGN_LOG"
for arg in "$@"; do
	case "$arg" in
	--verify) exit 0 ;;
	-dv)
		echo "Authority=${FAKE_AUTHORITY:-Developer ID Application: Test Person (TEAM123456)}" >&2
		echo "TeamIdentifier=${FAKE_TEAM:-TEAM123456}" >&2
		exit 0
		;;
	esac
done
count_file="$FAKE_CODESIGN_LOG.count"
n=$(($(cat "$count_file" 2>/dev/null || echo 0) + 1))
echo "$n" >"$count_file"
if [ "$n" -le "${FAKE_FAIL_FIRST:-0}" ]; then exit 1; fi
exit 0
FAKE
cat >"$fake_devid/security" <<'FAKE'
#!/bin/sh
cat <<'OUT'
  1) 1111111111111111111111111111111111111111 "Apple Development: Someone (AAAAAAAAAA)"
  2) 2222222222222222222222222222222222222222 "Developer ID Application: Test Person (TEAM123456)"
  3) 3333333333333333333333333333333333333333 "Developer ID Application: Other Person (TEAM999999)"
     3 valid identities found
OUT
FAKE
chmod 755 "$fake_cs/codesign" "$fake_devid/security"
devid_hash=2222222222222222222222222222222222222222

# Runs the injector on a fresh stand-in app with the fake codesign. $1 names the run; "devid" puts a Developer ID
# in the fake keychain, anything else none. More arguments go to the injector. The log is $work/fake-$1.log and
# the output $work/fake-$1.out; the status is in $fake_status.
fake_run() {
	local name="$1" keychain="$2" bin
	shift 2
	if [ "$keychain" = "devid" ]; then bin="$fake_devid"; else bin="$no_identity_bin"; fi
	fake_app="$(new_app "fake-$name")"
	fake_log="$work/fake-$name.log"
	: >"$fake_log"
	rm -f "$fake_log.count"
	set +e
	PATH="$fake_cs:$bin:$PATH" FAKE_CODESIGN_LOG="$fake_log" COURIER_SECRETS_DIR="$empty_store" \
		"$injector" --allow-missing "$@" "$fake_app" >"$work/fake-$name.out" 2>&1
	fake_status=$?
	set -e
}
# Whether the logged call $1 (arguments joined with "|") has the argument $2.
has() {
	case "|$1|" in *"|$2|"*) return 0 ;; esac
	return 1
}
# The lines of the log that sign something.
signing_lines() { grep -- '--sign' "$1" || true; }
engine_line() { signing_lines "$1" | grep -- '/Contents/Helpers/courier-engine$' | head -1; }
app_line() { signing_lines "$1" | grep -- "Courier.app\$" | head -1; }

# 11a. A Developer ID is found in the keychain and used, by its hash.
fake_run devid devid
[ "$fake_status" -eq 0 ] && ok "signing with a Developer ID exits 0" || fail "signing with a Developer ID exited $fake_status: $(cat "$work/fake-devid.out")"
engine="$(engine_line "$fake_log")"
application="$(app_line "$fake_log")"
[ -n "$engine" ] && [ -n "$application" ] && ok "the engine and the app were each signed once" || fail "the engine or the app was not signed: $(cat "$fake_log")"
first_signing="$(signing_lines "$fake_log" | head -1)"
[ "$first_signing" = "$engine" ] && ok "the engine is signed before the app" || fail "the first signing was not the engine's: $first_signing"
[ "$(signing_lines "$fake_log" | tail -1)" = "$application" ] && ok "the app is signed last" || fail "the app was not signed last"
for line in "$engine" "$application"; do
	if ! (has "$line" --force && has "$line" --options && has "$line" runtime && has "$line" --timestamp && has "$line" "$devid_hash"); then
		fail "a Developer ID signing lacks --force, --options runtime, --timestamp or the identity: $line"
	fi
done
ok "both are signed with --force --options runtime --timestamp and the first Developer ID"
case "|$engine|" in *"|--identifier|com.vitruviansoftware.courier.engine|"*) ok "the engine has its own identifier" ;; *) fail "the engine has no identifier: $engine" ;; esac
case "|$application|" in *"|--identifier|"*) fail "the app was given an identifier: $application" ;; *) ok "the app keeps its bundle identifier" ;; esac
case "|$engine|" in *"|--entitlements|"*) fail "the engine was given entitlements: $engine" ;; *) ok "the engine has no entitlements of its own" ;; esac
case "$application" in
*"|--entitlements|"*"/Resources/Courier.entitlements|"*) ok "the app is signed with Resources/Courier.entitlements" ;;
*) fail "the app is not signed with Resources/Courier.entitlements: $application" ;;
esac
if has "$engine" --strip-disallowed-xattrs && has "$application" --strip-disallowed-xattrs; then
	ok "both Developer ID signatures pass --strip-disallowed-xattrs"
else
	fail "a Developer ID signature lacks --strip-disallowed-xattrs"
fi
if grep -q -- '--deep' <(grep -v -- '--verify' "$fake_log"); then fail "--deep was used to sign"; else ok "no signing uses --deep"; fi
grep -q -- '--verify|--deep|--strict' "$fake_log" && ok "the result is checked with --verify --deep --strict" || fail "the result was not verified"
grep -q 'Signed .* with Developer ID (team TEAM123456)' "$work/fake-devid.out" && ok "it says it used a Developer ID, and the team" || fail "it did not say it used a Developer ID: $(cat "$work/fake-devid.out")"
if grep -q "$devid_hash" "$work/fake-devid.out"; then fail "it printed the identity hash"; else ok "it did not print the identity hash"; fi

# 11b. With no identity in the keychain: ad hoc, still inside out, no runtime and no timestamp.
fake_run adhoc none
[ "$fake_status" -eq 0 ] && ok "signing ad hoc exits 0" || fail "signing ad hoc exited $fake_status"
engine="$(engine_line "$fake_log")"
application="$(app_line "$fake_log")"
[ "$(signing_lines "$fake_log" | head -1)" = "$engine" ] && [ "$(signing_lines "$fake_log" | tail -1)" = "$application" ] &&
	ok "ad hoc also signs the engine, then the app" || fail "ad hoc did not sign the engine then the app: $(cat "$fake_log")"
if has "$engine" --strip-disallowed-xattrs && has "$application" --strip-disallowed-xattrs; then
	ok "ad hoc strips disallowed attributes too"
else
	fail "ad hoc lacks --strip-disallowed-xattrs"
fi
case "$engine$application" in *"--options"* | *"--timestamp"*) fail "an ad hoc signing asked for the runtime or a timestamp" ;; *) ok "ad hoc asks for neither the hardened runtime nor a timestamp" ;; esac
case "|$engine|$application|" in *"|--sign|-|"*"|--sign|-|"*) ok "both are signed with the ad hoc identity" ;; *) fail "not both ad hoc: $engine / $application" ;; esac
case "|$engine|" in *"|--identifier|com.vitruviansoftware.courier.engine|"*) ok "the engine has its identifier ad hoc too" ;; *) fail "no identifier ad hoc" ;; esac
case "$application" in *"|--entitlements|"*) ok "the app has its entitlements ad hoc too" ;; *) fail "no entitlements ad hoc" ;; esac
grep -q 'Signed .* ad hoc' "$work/fake-adhoc.out" && ok "it says it signed ad hoc" || fail "it did not say ad hoc: $(cat "$work/fake-adhoc.out")"

# 11c. COURIER_SIGN_IDENTITY="-" forces ad hoc, even with a Developer ID installed.
COURIER_SIGN_IDENTITY="-" fake_run forced devid
case "$(signing_lines "$fake_log" | tr '\n' ' ')" in
*"--options"* | *"--timestamp"* | *"$devid_hash"*) fail "COURIER_SIGN_IDENTITY=- did not force ad hoc: $(cat "$fake_log")" ;;
*"--sign|-|"*) ok "COURIER_SIGN_IDENTITY=- forces ad hoc" ;;
*) fail "COURIER_SIGN_IDENTITY=- gave an unexpected signing: $(cat "$fake_log")" ;;
esac

# 11c2. The same certificate listed twice (it is in two keychains): one hash, used for both signatures.
dup_bin="$work/bin-devid-twice"
mkdir -p "$dup_bin"
cat >"$dup_bin/security" <<'FAKE'
#!/bin/sh
cat <<'OUT'
  1) 2222222222222222222222222222222222222222 "Developer ID Application: Test Person (TEAM123456)"
  2) 2222222222222222222222222222222222222222 "Developer ID Application: Test Person (TEAM123456)"
     2 valid identities found
OUT
FAKE
chmod 755 "$dup_bin/security"
fake_devid_saved="$fake_devid"
fake_devid="$dup_bin"
fake_run dup devid
fake_devid="$fake_devid_saved"
if [ "$fake_status" -eq 0 ] && has "$(engine_line "$fake_log")" "$devid_hash" && has "$(app_line "$fake_log")" "$devid_hash" &&
	[ "$(signing_lines "$fake_log" | grep -c -- "$devid_hash")" -eq 2 ]; then
	ok "a certificate listed twice gives one hash, used for both signatures"
else
	fail "a duplicated certificate was not handled: $(cat "$fake_log")"
fi

# 11d. COURIER_SIGN_IDENTITY names another identity: that one, with the runtime and a timestamp.
COURIER_SIGN_IDENTITY="Some Identity" fake_run named devid
if has "$(engine_line "$fake_log")" "Some Identity" && has "$(engine_line "$fake_log")" runtime && has "$(app_line "$fake_log")" "Some Identity"; then
	ok "COURIER_SIGN_IDENTITY picks the identity"
else
	fail "COURIER_SIGN_IDENTITY was not used: $(cat "$fake_log")"
fi

# 11e. COURIER_SIGN_FLAGS reach both signatures.
COURIER_SIGN_FLAGS="--prefix=com.example." fake_run flags devid
n="$(signing_lines "$fake_log" | grep -c -- '--prefix=com.example.' || true)"
[ "$n" -eq 2 ] && ok "COURIER_SIGN_FLAGS go to both signatures" || fail "COURIER_SIGN_FLAGS reached $n of 2 signatures"

# 11f. A timestamp that fails once is tried again; one that never works fails the run.
FAKE_FAIL_FIRST=1 fake_run retry devid
n="$(signing_lines "$fake_log" | wc -l | tr -d ' ')"
if [ "$fake_status" -eq 0 ] && [ "$n" -eq 3 ]; then ok "a failed signing is tried again"; else fail "a failed signing was not retried ($fake_status, $n signings)"; fi
FAKE_FAIL_FIRST=99 fake_run giveup devid
n="$(signing_lines "$fake_log" | wc -l | tr -d ' ')"
if [ "$fake_status" -eq 1 ] && [ "$n" -eq 3 ]; then ok "three failures give up with exit 1"; else fail "three failures gave exit $fake_status after $n signings"; fi
FAKE_FAIL_FIRST=1 fake_run noretry none
if [ "$fake_status" -eq 1 ]; then ok "an ad hoc failure is not retried (there is no timestamp to blame)"; else fail "an ad hoc failure was retried or ignored"; fi

# 11g. --entitlements names another file.
other_ents="$work/Other.entitlements"
cp "$ents" "$other_ents"
fake_run ents devid --entitlements "$other_ents"
case "$(app_line "$fake_log")" in *"|--entitlements|$other_ents|"*) ok "--entitlements picks the file" ;; *) fail "--entitlements was ignored" ;; esac
set +e
"$injector" --entitlements "$work/no-such.entitlements" "$(new_app no-ents)" >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "a missing entitlements file is a usage error" || fail "a missing entitlements file was not a usage error"
set -e

# 11h. The real entitlements file (when given) is well formed, grants exactly the three resources README.md lists
# (nothing more), and the injector finds it by itself.
if [ -n "$real_entitlements" ]; then
	plutil -lint "$real_entitlements" >/dev/null 2>&1 && ok "Courier.entitlements is a well-formed property list" || fail "Courier.entitlements is malformed"
	nkeys=$(plutil -convert json -o - "$real_entitlements" 2>/dev/null | grep -o '"com\.apple\.[^"]*"' | wc -l | tr -d ' ')
	[ "$nkeys" = 3 ] && ok "Courier.entitlements grants exactly what README.md lists" || fail "Courier.entitlements differs from README.md's list (microphone, Contacts, Calendars): update both together"
	fake_run default devid
	case "$(app_line "$fake_log")" in *"/Resources/Courier.entitlements|"*) ok "the injector finds Resources/Courier.entitlements beside its scripts folder" ;; *) fail "the default entitlements file was not used" ;; esac
fi

# The hardened runtime refuses the microphone, Contacts and Calendars to an app that does not
# declare them, without asking the person: the real entitlements must name all three.
if [ -n "$real_entitlements" ]; then
	for key in com.apple.security.device.audio-input com.apple.security.personal-information.addressbook com.apple.security.personal-information.calendars; do
		if [ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$real_entitlements" 2>/dev/null)" = "true" ]; then
			ok "Courier.entitlements grants $key"
		else
			fail "Courier.entitlements lacks $key: the hardened runtime would refuse it without a prompt"
		fi
	done
fi

exit "$failed"
