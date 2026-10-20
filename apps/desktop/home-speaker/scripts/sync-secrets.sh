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
#   bazel run //apps/desktop/home-speaker:sync-secrets -- --extension
#   bazel run //apps/desktop/home-speaker:sync-secrets -- --beeper [--extension]
#   bazel run //apps/desktop/home-speaker:sync-secrets -- --gemini [--extension]
#
# --beeper puts the Beeper Desktop API token there instead, as `beeperToken`:
# from the item "Beeper Desktop API" (or --item), its custom field `token`, or
# else its password. Make the token in Beeper Desktop under Settings >
# Integrations > Approved connections.
#
# --gemini puts a Gemini API key there instead, as `geminiApiKey`, for the
# announcement rewrite and the Gemini voice on this Mac: from the item
# "Gemini API" (or --item), its custom field `token` or `api_key`, else its
# password, else the one AIza... key in its notes. Both read the key at each
# announcement, so nothing restarts.
#
# Reads the Slack USER token (xoxp-) from a Bitwarden item -- its notes, custom
# fields or password, wherever it is -- and writes it as `slackToken` into
# HomeSpeaker's secrets file, keeping every other key. The user token, not the
# bot token: HomeSpeaker polls `search.messages`, which Slack only allows with
# a user token's `search:read` scope.
#
# --extension fills the HomeSpeaker Vitruvian extension's own secrets.json
# instead of the app's. The extension keeps it in its data folder, which the
# choice file (~/.gemini/speaker_door.json, "extension.data_folder") names. If
# that file, its extension block or the folder is missing this stops and writes
# nothing; it never falls back to the app's file. The app is not restarted.
#
# The Bitwarden session is the one //tools/sync-env-secrets caches; if the
# vault is locked this stops and says to run :unlock rather than prompting.
#
# The token value is never printed, passed on a command line, or logged:
# it travels in an environment variable to jq and lands in a 0600 file.
set -euo pipefail

ITEM=""
BEEPER=0
GEMINI=0
RESTART=1
DRY_RUN=0
EXTENSION=0
CHOICE_FILE="$HOME/.gemini/speaker_door.json"
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
	--extension)
		EXTENSION=1
		shift
		;;
	--beeper)
		BEEPER=1
		shift
		;;
	--gemini)
		GEMINI=1
		shift
		;;
	-h | --help)
		sed -n '22,59p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*) die "unknown argument: $1 (try --help)" ;;
	esac
done

[ $((BEEPER + GEMINI)) -le 1 ] || die "--beeper and --gemini are one token each; pass one"

# Which token: Slack's user token, Beeper's, or a Gemini API key.
if [ "$GEMINI" -eq 1 ]; then
	KEY=geminiApiKey
	WHAT="Gemini API key"
	[ -n "$ITEM" ] || ITEM="Gemini API"
elif [ "$BEEPER" -eq 1 ]; then
	KEY=beeperToken
	WHAT="Beeper token"
	[ -n "$ITEM" ] || ITEM="Beeper Desktop API"
else
	KEY=slackToken
	WHAT="Slack user token"
	[ -n "$ITEM" ] || ITEM="Abrial Slack MCP"
fi

command -v bw >/dev/null || die "the Bitwarden CLI (bw) is not installed"
command -v jq >/dev/null || die "jq is not installed"

# --- which secrets file: the app's, or the extension's -------------------------
if [ "$EXTENSION" -eq 1 ]; then
	WHO="the HomeSpeaker extension"
	[ -f "$CHOICE_FILE" ] || die "no choice file at $CHOICE_FILE -- open the HomeSpeaker extension in Vitruvian first (nothing written)"
	DATA_FOLDER="$(jq -r '.extension.data_folder // ""' "$CHOICE_FILE" 2>/dev/null)" ||
		die "$CHOICE_FILE is not readable JSON (nothing written)"
	[ -n "$DATA_FOLDER" ] || die "$CHOICE_FILE has no extension.data_folder -- open the HomeSpeaker extension in Vitruvian first (nothing written)"
	[ -d "$DATA_FOLDER" ] || die "the extension's data folder does not exist: $DATA_FOLDER (nothing written)"
	SECRETS="$DATA_FOLDER/secrets.json"
else
	WHO="HomeSpeaker"
fi

# --- an unlocked session, without prompting -------------------------------
bw_unlocked() { [ "$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null)" = unlocked ]; }
if ! { [ -n "${BW_SESSION:-}" ] && bw_unlocked; }; then
	if [ -r "$SESS_CACHE" ]; then
		BW_SESSION="$(cat "$SESS_CACHE")"
		export BW_SESSION
	fi
	bw_unlocked || die "Bitwarden is locked. Run: bazel run //tools/sync-env-secrets:unlock"
fi

# --- the token, from wherever the item keeps it -----------------------------
ITEM_JSON="$(bw get item "$ITEM" 2>/dev/null)" || die "no Bitwarden item named \"$ITEM\" (pass --item)"
if [ "$GEMINI" -eq 1 ]; then
	# The custom field `token` or `api_key`, else the password, else the one
	# distinct Google API key (AIza...) in the notes.
	TOKENS="$(jq -r '([.fields // [] | .[] | select(.name == "token" or .name == "api_key") | .value // ""] | map(select(. != "")) | first)
		// (.login.password // "")' <<<"$ITEM_JSON" | tr -d '[:space:]')"
	if [ -z "$TOKENS" ]; then
		NOTES="$(jq -r '.notes // ""' <<<"$ITEM_JSON")"
		TOKENS="$(printf '%s\n' "$NOTES" | grep -oE 'GEMINI_API_KEY=AIza[0-9A-Za-z_-]{35}' | sed 's/^GEMINI_API_KEY=//' | sort -u || true)"
		if [ -z "$TOKENS" ]; then
			TOKENS="$(printf '%s\n' "$NOTES" | grep -oE 'AIza[0-9A-Za-z_-]{35}' | sort -u || true)"
		fi
		unset NOTES
		COUNT="$(printf '%s' "$TOKENS" | grep -c . || true)"
		[ "$COUNT" -le 1 ] || die "Bitwarden item \"$ITEM\" holds $COUNT Gemini API keys (AIza...) in its notes; want exactly one"
	fi
	[ -n "$TOKENS" ] || die "Bitwarden item \"$ITEM\" has no Gemini API key (a custom field named token or api_key, the password, or one AIza... key in the notes)"
elif [ "$BEEPER" -eq 1 ]; then
	# The custom field `token`, else the password; one line, nothing else.
	TOKENS="$(jq -r '([.fields // [] | .[] | select(.name == "token") | .value // ""] | map(select(. != "")) | first)
		// (.login.password // "")' <<<"$ITEM_JSON" | tr -d '[:space:]')"
	[ -n "$TOKENS" ] || die "Bitwarden item \"$ITEM\" has no Beeper token (a custom field named token, or the password)"
else
	# One distinct xoxp- token, across notes, custom fields and the password.
	TOKENS="$(jq -r '[.notes // "", (.fields // [] | map(.value // "") | .[]), (.login.password // "")]
		| join("\n")' <<<"$ITEM_JSON" | grep -oE 'xoxp-[A-Za-z0-9-]+' | sort -u || true)"
	COUNT="$(printf '%s' "$TOKENS" | grep -c . || true)"
	[ "$COUNT" -eq 1 ] || die "Bitwarden item \"$ITEM\" holds $COUNT Slack user tokens (xoxp-); want exactly one"
fi
export HS_TOKEN="$TOKENS"
unset TOKENS ITEM_JSON

# --- merge into the secrets file -----------------------------------------------
# The app's file must already exist (sign in first). The extension has no
# sign-in before this, so its file is created, 0600, when its folder has none.
if [ ! -f "$SECRETS" ]; then
	[ "$EXTENSION" -eq 1 ] || die "no HomeSpeaker secrets file at $SECRETS -- open HomeSpeaker and sign in first"
	CURRENT=""
else
	CURRENT="$(KEY="$KEY" jq -r '.[env.KEY] // ""' "$SECRETS")"
fi
if [ "$CURRENT" = "$HS_TOKEN" ]; then
	unset CURRENT HS_TOKEN
	if [ "$GEMINI" -eq 1 ]; then
		echo "Gemini API key already matches Bitwarden item \"$ITEM\" -- nothing to do."
	elif [ "$BEEPER" -eq 1 ]; then
		echo "Beeper token already matches Bitwarden item \"$ITEM\" -- nothing to do."
	else
		echo "Slack token already matches Bitwarden item \"$ITEM\" -- nothing to do."
	fi
	exit 0
fi
unset CURRENT
if [ "$DRY_RUN" -eq 1 ]; then
	echo "Would write the $WHAT from Bitwarden item \"$ITEM\" to $SECRETS (dry run)."
	exit 0
fi

TMP="$(dirname "$SECRETS")/.secrets.json.sync-$$"
trap 'rm -f "$TMP"' EXIT
(
	umask 077
	if [ -f "$SECRETS" ]; then
		KEY="$KEY" jq '.[env.KEY] = env.HS_TOKEN' "$SECRETS" >"$TMP"
	else
		KEY="$KEY" jq -n '{(env.KEY): env.HS_TOKEN}' >"$TMP"
	fi
)
chmod 600 "$TMP"
mv -f "$TMP" "$SECRETS"
trap - EXIT
unset HS_TOKEN
echo "$WHAT from Bitwarden item \"$ITEM\" written to $WHO."

# The Gemini key is read at each announcement: nothing to restart.
[ "$GEMINI" -eq 0 ] || exit 0

# The extension is not a process this script can restart; its chat monitor, like
# the app's, reads the token when it starts.
if [ "$EXTENSION" -eq 1 ]; then
	echo "Restart the extension's chat monitor if it is running, so it picks the token up."
	exit 0
fi

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
