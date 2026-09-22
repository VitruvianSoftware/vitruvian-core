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

# Puts HomeSpeaker's Slack token on this Mac from Bitwarden, so the vault is
# the one place it lives and nobody pastes it into Settings (or hard-codes it
# into a script, which is how Slack announcements worked until 2026-09-21).
#
#   bazel run //apps/desktop/home-speaker:sync-secrets
#   bazel run //apps/desktop/home-speaker:sync-secrets -- --item "My Slack" --no-restart
#
# Reads the Slack USER token (xoxp-) from a Bitwarden item -- its notes, custom
# fields or password, wherever it is -- and writes it as `slackToken` into
# HomeSpeaker's secrets file, keeping every other key. The user token, not the
# bot token: HomeSpeaker polls `search.messages`, which Slack only allows with
# a user token's `search:read` scope.
#
# The Bitwarden session is the one //tools/sync-env-secrets caches; if the
# vault is locked this stops and says to run :unlock rather than prompting.
#
# The token value is never printed, passed on a command line, or logged:
# it travels in an environment variable to jq and lands in a 0600 file.
set -euo pipefail

ITEM="Abrial Slack MCP"
RESTART=1
DRY_RUN=0
SECRETS="${HOMESPEAKER_SECRETS:-$HOME/Library/Application Support/HomeSpeaker/secrets.json}"
SESS_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/vitruvian-core/bw-session"

die() {
	echo "sync-secrets: $*" >&2
	exit 1
}

while [ $# -gt 0 ]; do
	case "$1" in
	--item)
		ITEM="${2:?--item needs a Bitwarden item name}"
		shift 2
		;;
	--no-restart)
		RESTART=0
		shift
		;;
	--dry-run)
		DRY_RUN=1
		shift
		;;
	-h | --help)
		sed -n '22,40p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*) die "unknown argument: $1 (try --help)" ;;
	esac
done

command -v bw >/dev/null || die "the Bitwarden CLI (bw) is not installed"
command -v jq >/dev/null || die "jq is not installed"

# --- an unlocked session, without prompting -------------------------------
bw_unlocked() { [ "$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null)" = unlocked ]; }
if ! { [ -n "${BW_SESSION:-}" ] && bw_unlocked; }; then
	if [ -r "$SESS_CACHE" ]; then
		BW_SESSION="$(cat "$SESS_CACHE")"
		export BW_SESSION
	fi
	bw_unlocked || die "Bitwarden is locked. Run: bazel run //tools/sync-env-secrets:unlock"
fi

# --- the user token, from wherever the item keeps it ------------------------
ITEM_JSON="$(bw get item "$ITEM" 2>/dev/null)" || die "no Bitwarden item named \"$ITEM\" (pass --item)"
# One distinct xoxp- token, across notes, custom fields and the password.
TOKENS="$(jq -r '[.notes // "", (.fields // [] | map(.value // "") | .[]), (.login.password // "")]
	| join("\n")' <<<"$ITEM_JSON" | grep -oE 'xoxp-[A-Za-z0-9-]+' | sort -u || true)"
COUNT="$(printf '%s' "$TOKENS" | grep -c . || true)"
[ "$COUNT" -eq 1 ] || die "Bitwarden item \"$ITEM\" holds $COUNT Slack user tokens (xoxp-); want exactly one"
export HS_SLACK_TOKEN="$TOKENS"
unset TOKENS ITEM_JSON

# --- merge into HomeSpeaker's secrets file ------------------------------------
[ -f "$SECRETS" ] || die "no HomeSpeaker secrets file at $SECRETS -- open HomeSpeaker and sign in first"
CURRENT="$(jq -r '.slackToken // ""' "$SECRETS")"
if [ "$CURRENT" = "$HS_SLACK_TOKEN" ]; then
	unset CURRENT HS_SLACK_TOKEN
	echo "Slack token already matches Bitwarden item \"$ITEM\" -- nothing to do."
	exit 0
fi
unset CURRENT
if [ "$DRY_RUN" -eq 1 ]; then
	echo "Would write the Slack user token from Bitwarden item \"$ITEM\" to $SECRETS (dry run)."
	exit 0
fi

TMP="$(dirname "$SECRETS")/.secrets.json.sync-$$"
trap 'rm -f "$TMP"' EXIT
(
	umask 077
	jq '.slackToken = env.HS_SLACK_TOKEN' "$SECRETS" >"$TMP"
)
chmod 600 "$TMP"
mv -f "$TMP" "$SECRETS"
trap - EXIT
unset HS_SLACK_TOKEN
echo "Slack user token from Bitwarden item \"$ITEM\" written to HomeSpeaker."

# --- make the running app use it ---------------------------------------------
# The chat monitor reads secrets when it starts, so a running app keeps the old
# (or no) token until it restarts.
#
# Relaunching straight after the process exits fails with LaunchServices error
# -600 while it is still tearing the old instance down -- which left the app
# NOT running the first time this ran for real. So: wait for the exit, then
# retry the launch, and fail loudly if it never comes back.
BUNDLE_ID=com.vitruviansoftware.homespeaker
if [ "$RESTART" -eq 1 ] && pgrep -x HomeSpeaker >/dev/null; then
	pkill -x HomeSpeaker || true
	for _ in $(seq 1 20); do
		pgrep -x HomeSpeaker >/dev/null || break
		sleep 0.25
	done
	for _ in $(seq 1 10); do
		open -b "$BUNDLE_ID" 2>/dev/null || true
		sleep 1
		if pgrep -x HomeSpeaker >/dev/null; then
			echo "HomeSpeaker restarted so the chat monitor picks it up."
			exit 0
		fi
	done
	die "the token is saved, but HomeSpeaker did not restart -- open it from /Applications"
fi
