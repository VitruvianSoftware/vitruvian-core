#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Antigravity runs this after each model invocation (see ../hooks.json).
# It records a lightweight JSON note in ~/.gemini/antigravity/receipts-report-inbox
# with the conversationId, workspacePaths, modelName, and step count so the
# receipts-report sidecar can index active conversations without full directory
# walks on every poll.
#
# Always exits 0 and prints `{}` so it never alters or blocks agent execution.

payload=$(cat)
printf '{}'

case "$payload" in *'"conversationId"'*) ;; *) exit 0 ;; esac

inbox="${ANTIGRAVITY_APP_DATA_DIR:-$HOME/.gemini/antigravity}/receipts-report-inbox"
mkdir -p "$inbox" 2>/dev/null || exit 0
note="$inbox/$(date +%s)-$$.json"
printf '%s' "$payload" >"$note.tmp" 2>/dev/null && mv "$note.tmp" "$note" 2>/dev/null
exit 0
