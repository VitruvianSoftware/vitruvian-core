#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Antigravity runs this on SessionStart (see ../hooks.json). It records the
# active workspace paths and conversationId into
# ~/.gemini/antigravity/worktree-band-inbox/ so the worktree-band sidecar can
# automatically discover and monitor the conversation's git worktrees.
#
# The logic is in src/lib.rs; rust-hook.sh builds and runs it. If it cannot,
# the message below tells the agent the worktree is not being tracked.

exec "$(dirname "$0")/rust-hook.sh" session_worktree main.rs \
	'{"injectSteps":[{"ephemeralMessage":"worktree-band could not run: its hook is still being built with rustc, or cannot be (details in ~/.cache/antigravity-plugins). The worktree of this conversation is not being tracked."}]}'
