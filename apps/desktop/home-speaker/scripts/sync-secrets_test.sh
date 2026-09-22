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
# value ever reaches stdout or stderr.
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
	grep -q -e "$USER_TOK" -e "$BOT_TOK" "$WORK/out" && fail "$1: a token value was printed" || true
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

echo "PASS"
