#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Antigravity runs this hook after `invoke_subagent` or `send_message` tool calls
# (see ../hooks.json). It writes an atomic event note into
# ~/.gemini/antigravity/savvy-fleet-inbox/ so the savvy-fleet sidecar panel can
# immediately display subagent launches, roles, tiers, and messages alongside
# live transcript inspection.
#
# It must stay fast and never fail: hooks run inside the agent's loop and only
# output `{}`.

payload=$(cat)
printf '{}'

case "$payload" in
*'invoke_subagent'* | *'send_message'*) ;;
*) exit 0 ;;
esac

inbox="${ANTIGRAVITY_APP_DATA_DIR:-$HOME/.gemini/antigravity}/savvy-fleet-inbox"
mkdir -p "$inbox" 2>/dev/null || exit 0
note="$inbox/$(date +%s)-$$.json"
printf '%s' "$payload" >"$note.tmp" 2>/dev/null && mv "$note.tmp" "$note" 2>/dev/null
exit 0
