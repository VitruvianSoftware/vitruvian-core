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

# sync-secrets.sh against a fake `bw`, a temp secrets file and no real vault.
# Pins: the USER token is chosen over the bot token, every other key in the
# secrets file survives, the file stays 0600, a second run is a no-op, an item
# that does not hold exactly one user token changes nothing, and no token
# value ever reaches stdout or stderr. With --extension the token goes into the
# HomeSpeaker extension's own secrets.json (the data folder the choice file,
# ~/.gemini/speaker_door.json, names) and never into the app's; without a
# usable choice file it fails and writes nothing, never falling back to the app.
# With --beeper the Beeper Desktop API token (custom field `token`, else the
# password) goes in as beeperToken, beside the Slack token, under the same rules.
set -euo pipefail

SCRIPT="${TEST_SRCDIR:-}/${TEST_WORKSPACE:-_main}/apps/desktop/home-speaker/scripts/sync-secrets.sh"
[ -f "$SCRIPT" ] || SCRIPT="$(cd "$(dirname "$0")" && pwd)/sync-secrets.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
export HOME="$WORK/home" XDG_CACHE_HOME="$WORK/cache"
mkdir -p "$HOME"
export HOMESPEAKER_SECRETS="$WORK/secrets.json"
# `bw status` is unlocked; `bw get item <name>` serves $WORK/items/<name>.json.
cat >"$WORK/bin/bw" <<'STUB'
#!/usr/bin/env bash
case "$1" in
status) echo '{"status":"unlocked"}' ;;
get) f="$FAKE_ITEMS/$3.json"; [ -f "$f" ] && cat "$f" || exit 1 ;;
*) exit 2 ;;
esac
STUB
# pgrep says HomeSpeaker is not running, so the test never kills a real app.
printf '#!/bin/sh\nexit 1\n' >"$WORK/bin/pgrep"
chmod +x "$WORK/bin/bw" "$WORK/bin/pgrep"
export PATH="$WORK/bin:$PATH" FAKE_ITEMS="$WORK/items"
mkdir -p "$FAKE_ITEMS"
export BW_SESSION=fake

USER_TOK="xoxp-1111-2222-3333-aaaaaaaa"
BOT_TOK="xoxb-9999-8888-bbbbbbbb"
cat >"$FAKE_ITEMS/Abrial Slack MCP.json" <<JSON
{"name":"Abrial Slack MCP","notes":"bot: $BOT_TOK\nuser: $USER_TOK\n"}
JSON
cat >"$FAKE_ITEMS/Two Users.json" <<JSON
{"name":"Two Users","notes":"$USER_TOK xoxp-4444-5555-cccccccc"}
JSON
cat >"$FAKE_ITEMS/Bot Only.json" <<JSON
{"name":"Bot Only","fields":[{"name":"t","value":"$BOT_TOK"}]}
JSON
cat >"$FAKE_ITEMS/In A Field.json" <<JSON
{"name":"In A Field","fields":[{"name":"user","value":"$USER_TOK"}]}
JSON
# Made-up Beeper tokens. # gitleaks:allow (made-up test tokens)
BEEPER_TOK="fake-beeper-field-token-0001"   # gitleaks:allow (made-up test token)
BEEPER_PW="fake-beeper-password-token-0002" # gitleaks:allow (made-up test token)
cat >"$FAKE_ITEMS/Beeper Desktop API.json" <<JSON
{"name":"Beeper Desktop API","fields":[{"name":"other","value":"nope"},{"name":"token","value":"$BEEPER_TOK"}],"login":{"password":"$BEEPER_PW"}}
JSON
cat >"$FAKE_ITEMS/Beeper Password.json" <<JSON
{"name":"Beeper Password","login":{"password":"$BEEPER_PW"}}
JSON
cat >"$FAKE_ITEMS/Beeper Empty.json" <<JSON
{"name":"Beeper Empty","fields":[{"name":"token","value":""}],"login":{"password":""}}
JSON

fail() {
	echo "FAIL: $*" >&2
	exit 1
}
reset() {
	printf '{"google":{"refreshToken":"g"},"googleChat":{"refreshToken":"c"}}' >"$HOMESPEAKER_SECRETS"
	chmod 600 "$HOMESPEAKER_SECRETS"
}
run() { bash "$SCRIPT" "$@" >"$WORK/out" 2>&1; }
no_leak() {
	grep -q -e "$USER_TOK" -e "$BOT_TOK" -e "$BEEPER_TOK" -e "$BEEPER_PW" "$WORK/out" && fail "$1: a token value was printed" || true
}

# 1. the user token wins, other keys survive, mode stays 0600
reset
run || {
	cat "$WORK/out"
	fail "default item run failed"
}
no_leak "write"
[ "$(jq -r .slackToken "$HOMESPEAKER_SECRETS")" = "$USER_TOK" ] || fail "slackToken is not the xoxp user token"
[ "$(jq -r .google.refreshToken "$HOMESPEAKER_SECRETS")" = g ] || fail "google login was dropped"
[ "$(jq -r .googleChat.refreshToken "$HOMESPEAKER_SECRETS")" = c ] || fail "googleChat login was dropped"
[ "$(stat -f %Lp "$HOMESPEAKER_SECRETS" 2>/dev/null || stat -c %a "$HOMESPEAKER_SECRETS")" = 600 ] || fail "secrets file is not 0600"

# 2. a second run changes nothing
before="$(shasum "$HOMESPEAKER_SECRETS")"
run || fail "second run failed"
grep -q "nothing to do" "$WORK/out" || fail "second run did not say it was a no-op"
[ "$(shasum "$HOMESPEAKER_SECRETS")" = "$before" ] || fail "second run rewrote the file"

# 3. a token kept in a custom field is found too
reset
run --item "In A Field" || fail "token in a custom field was not found"
[ "$(jq -r .slackToken "$HOMESPEAKER_SECRETS")" = "$USER_TOK" ] || fail "field token not written"

# 4. zero or two user tokens: refuse, file untouched, nothing leaked
for item in "Bot Only" "Two Users" "No Such Item"; do
	reset
	before="$(shasum "$HOMESPEAKER_SECRETS")"
	if run --item "$item"; then fail "\"$item\" should have been refused"; fi
	no_leak "$item"
	[ "$(shasum "$HOMESPEAKER_SECRETS")" = "$before" ] || fail "\"$item\" changed the secrets file"
done

# 5. dry run writes nothing
reset
before="$(shasum "$HOMESPEAKER_SECRETS")"
run --dry-run || fail "dry run failed"
[ "$(shasum "$HOMESPEAKER_SECRETS")" = "$before" ] || fail "dry run wrote the file"

# --- --extension: the extension's file, never the app's ----------------------
# HOME is the scratch $WORK/home, so the choice file is $WORK/home/.gemini/...
DOOR="$HOME/.gemini/speaker_door.json"
EXT_DIR="$WORK/ext-data"
EXT_SECRETS="$EXT_DIR/secrets.json"
write_door() { # $1 = data folder to record
	mkdir -p "$HOME/.gemini"
	printf '{"version":1,"chosen":"extension","extension":{"program":"/p","data_folder":"%s","version":"1.19.0","door":1}}' "$1" >"$DOOR"
}
reset_ext() {
	mkdir -p "$EXT_DIR"
	printf '{"google":{"refreshToken":"ext-g"}}' >"$EXT_SECRETS"
	chmod 600 "$EXT_SECRETS"
}

# 6. --extension writes the extension's file and not the app's
reset
reset_ext
write_door "$EXT_DIR"
app_before="$(shasum "$HOMESPEAKER_SECRETS")"
run --extension || {
	cat "$WORK/out"
	fail "--extension run failed"
}
no_leak "--extension write"
[ "$(jq -r .slackToken "$EXT_SECRETS")" = "$USER_TOK" ] || fail "--extension did not write the user token to the extension's file"
[ "$(jq -r .google.refreshToken "$EXT_SECRETS")" = ext-g ] || fail "--extension dropped the extension's other keys"
[ "$(stat -f %Lp "$EXT_SECRETS" 2>/dev/null || stat -c %a "$EXT_SECRETS")" = 600 ] || fail "extension secrets file is not 0600"
[ "$(shasum "$HOMESPEAKER_SECRETS")" = "$app_before" ] || fail "--extension touched the app's secrets file"
[ "$(jq -r '.slackToken // "none"' "$HOMESPEAKER_SECRETS")" = none ] || fail "--extension put the token in the app's file"
for leftover in "$EXT_DIR"/.secrets.json.sync-*; do
	[ -e "$leftover" ] && fail "--extension left a temp file behind"
done

# 6b. a second --extension run is a no-op
ext_before="$(shasum "$EXT_SECRETS")"
run --extension || fail "second --extension run failed"
grep -q "nothing to do" "$WORK/out" || fail "second --extension run did not say it was a no-op"
[ "$(shasum "$EXT_SECRETS")" = "$ext_before" ] || fail "second --extension run rewrote the file"

# 6c. no secrets file in the extension's folder yet: it is created (0600)
rm -f "$EXT_SECRETS"
run --extension || fail "--extension with no secrets file yet failed"
[ "$(jq -r .slackToken "$EXT_SECRETS")" = "$USER_TOK" ] || fail "new extension secrets file has no token"
[ "$(stat -f %Lp "$EXT_SECRETS" 2>/dev/null || stat -c %a "$EXT_SECRETS")" = 600 ] || fail "new extension secrets file is not 0600"

# 6d. --extension --dry-run writes nothing
reset_ext
ext_before="$(shasum "$EXT_SECRETS")"
run --extension --dry-run || fail "--extension dry run failed"
[ "$(shasum "$EXT_SECRETS")" = "$ext_before" ] || fail "--extension dry run wrote the file"
grep -q "$EXT_SECRETS" "$WORK/out" || fail "--extension dry run did not name the extension's file"

# 7. no usable choice file: fail clearly, write nothing anywhere, no fallback
refuse_ext() { # $1 = why
	reset
	reset_ext
	app_before="$(shasum "$HOMESPEAKER_SECRETS")"
	ext_before="$(shasum "$EXT_SECRETS")"
	if run --extension; then fail "--extension should have been refused: $1"; fi
	no_leak "--extension refused ($1)"
	grep -q "sync-secrets:" "$WORK/out" || fail "--extension refused ($1) without a clear message"
	[ "$(shasum "$HOMESPEAKER_SECRETS")" = "$app_before" ] || fail "--extension ($1) fell back to the app's file"
	[ "$(shasum "$EXT_SECRETS")" = "$ext_before" ] || fail "--extension ($1) changed the extension's file"
}
rm -f "$DOOR"
refuse_ext "no choice file"
printf '{"version":1,"chosen":"app"}' >"$DOOR"
refuse_ext "no extension block"
printf '{"version":1,"extension":{"program":"/p","version":"1.19.0"}}' >"$DOOR"
refuse_ext "no data_folder"
write_door "$WORK/no-such-folder"
refuse_ext "data folder missing"
[ ! -e "$WORK/no-such-folder" ] || fail "--extension created the missing data folder"
printf 'not json' >"$DOOR"
refuse_ext "choice file is not JSON"

# 8. without --extension the choice file is not consulted: the app's file is used
write_door "$EXT_DIR"
reset
reset_ext
ext_before="$(shasum "$EXT_SECRETS")"
run || fail "default run failed with a choice file present"
[ "$(jq -r .slackToken "$HOMESPEAKER_SECRETS")" = "$USER_TOK" ] || fail "default run did not write the app's file"
[ "$(shasum "$EXT_SECRETS")" = "$ext_before" ] || fail "default run touched the extension's file"

# --- --beeper: the Beeper token, beside the Slack one --------------------------
# 9. the item's `token` field wins over its password; Slack and the rest survive
reset
jq '.slackToken = "xoxp-kept"' "$HOMESPEAKER_SECRETS" >"$WORK/s" && mv "$WORK/s" "$HOMESPEAKER_SECRETS"
chmod 600 "$HOMESPEAKER_SECRETS"
run --beeper || {
	cat "$WORK/out"
	fail "--beeper run failed"
}
no_leak "--beeper write"
[ "$(jq -r .beeperToken "$HOMESPEAKER_SECRETS")" = "$BEEPER_TOK" ] || fail "--beeper did not write the token field"
[ "$(jq -r .slackToken "$HOMESPEAKER_SECRETS")" = xoxp-kept ] || fail "--beeper dropped the Slack token"
[ "$(jq -r .google.refreshToken "$HOMESPEAKER_SECRETS")" = g ] || fail "--beeper dropped the google login"
[ "$(stat -f %Lp "$HOMESPEAKER_SECRETS" 2>/dev/null || stat -c %a "$HOMESPEAKER_SECRETS")" = 600 ] || fail "--beeper: secrets file is not 0600"
grep -q "Beeper token from Bitwarden item \"Beeper Desktop API\"" "$WORK/out" || fail "--beeper did not say what it wrote"

# 9b. a second --beeper run is a no-op
before="$(shasum "$HOMESPEAKER_SECRETS")"
run --beeper || fail "second --beeper run failed"
grep -q "Beeper token already matches" "$WORK/out" || fail "second --beeper run did not say it was a no-op"
[ "$(shasum "$HOMESPEAKER_SECRETS")" = "$before" ] || fail "second --beeper run rewrote the file"

# 9c. no token field: the password
reset
run --beeper --item "Beeper Password" || fail "--beeper with only a password failed"
[ "$(jq -r .beeperToken "$HOMESPEAKER_SECRETS")" = "$BEEPER_PW" ] || fail "--beeper did not fall back to the password"

# 9d. nothing usable, or no such item: refused, file untouched
for item in "Beeper Empty" "No Such Item"; do
	reset
	before="$(shasum "$HOMESPEAKER_SECRETS")"
	if run --beeper --item "$item"; then fail "--beeper \"$item\" should have been refused"; fi
	no_leak "--beeper $item"
	[ "$(shasum "$HOMESPEAKER_SECRETS")" = "$before" ] || fail "--beeper \"$item\" changed the secrets file"
done

# 9e. --beeper --dry-run writes nothing
reset
before="$(shasum "$HOMESPEAKER_SECRETS")"
run --beeper --dry-run || fail "--beeper dry run failed"
[ "$(shasum "$HOMESPEAKER_SECRETS")" = "$before" ] || fail "--beeper dry run wrote the file"

# 9f. --beeper --extension: the extension's file, never the app's
write_door "$EXT_DIR"
reset
reset_ext
app_before="$(shasum "$HOMESPEAKER_SECRETS")"
run --beeper --extension || {
	cat "$WORK/out"
	fail "--beeper --extension run failed"
}
no_leak "--beeper --extension"
[ "$(jq -r .beeperToken "$EXT_SECRETS")" = "$BEEPER_TOK" ] || fail "--beeper --extension did not write the extension's file"
[ "$(jq -r .google.refreshToken "$EXT_SECRETS")" = ext-g ] || fail "--beeper --extension dropped the extension's other keys"
[ "$(shasum "$HOMESPEAKER_SECRETS")" = "$app_before" ] || fail "--beeper --extension touched the app's secrets file"

# 9g. without --beeper nothing of Beeper's is touched
reset
run || fail "default run failed"
[ "$(jq -r '.beeperToken // "none"' "$HOMESPEAKER_SECRETS")" = none ] || fail "a Slack run wrote a Beeper token"

echo "PASS"
