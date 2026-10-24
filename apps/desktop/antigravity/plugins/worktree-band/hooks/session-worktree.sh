#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Antigravity runs this on SessionStart (see ../hooks.json). It records the
# active workspace paths and conversationId into
# ~/.gemini/antigravity/worktree-band-inbox/ so the worktree-band sidecar can
# automatically discover and monitor the conversation's git worktrees.

payload=$(cat)
printf '{}'

case "$payload" in *'"workspacePaths"'* | *'"cwd"'* | *'"conversationId"'*) ;; *) exit 0 ;; esac

inbox="$HOME/.gemini/antigravity/worktree-band-inbox"
mkdir -p "$inbox" 2>/dev/null || exit 0
note="$inbox/$(date +%s)-$$.json"
printf '%s' "$payload" >"$note.tmp" 2>/dev/null && mv "$note.tmp" "$note" 2>/dev/null
exit 0
