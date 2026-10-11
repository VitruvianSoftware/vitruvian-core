#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Antigravity runs this after every shell command an agent runs (see
# ../hooks.json). When the command was `gh pr create`, it leaves a note for
# the gh-watch watcher, which then starts watching the new pull request for
# the conversation that opened it.
#
# It must stay fast and must never fail: hooks run inside the agent's loop.
# It only ever answers `{}`, which changes nothing about the command or its
# permissions.

payload=$(cat)
printf '{}'

case "$payload" in *'gh pr create'*) ;; *) exit 0 ;; esac
# Only the desktop app runs the watcher. The CLI and the IDE keep their
# conversations under other folders, and a note from them would never be read.
case "$payload" in *'/.gemini/antigravity/'*) ;; *) exit 0 ;; esac

# A fixed folder, not one inside the plugin's own data folder: that one is
# named after however the plugin was installed, which this script cannot know.
inbox="$HOME/.gemini/antigravity/gh-watch-inbox"
mkdir -p "$inbox" 2>/dev/null || exit 0
note="$inbox/$(date +%s)-$$.json"
# Write then rename, so the watcher never reads half a note.
printf '%s' "$payload" >"$note.tmp" 2>/dev/null && mv "$note.tmp" "$note" 2>/dev/null
exit 0
