#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Notices `agy plugin` commands run by an agent so the Extensions Marketplace
# sidecar knows when a plugin was installed, toggled, or removed from the CLI.

payload=$(cat)
printf '{}'

case "$payload" in
*'agy plugin'*) ;;
*) exit 0 ;;
esac

inbox="${ANTIGRAVITY_APP_DATA_DIR:-$HOME/.gemini/antigravity}/ext-marketplace-inbox"
mkdir -p "$inbox" 2>/dev/null || exit 0
note="$inbox/$(date +%s)-$$.json"
printf '%s' "$payload" >"$note.tmp" 2>/dev/null && mv "$note.tmp" "$note" 2>/dev/null
exit 0
