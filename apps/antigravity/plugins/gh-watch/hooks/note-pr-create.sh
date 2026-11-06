#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Antigravity runs this after every shell command an agent runs (see
# ../hooks.json). When the command was `gh pr create` (or the repo's
# `bazel run //tools/agent-app -- pr-create`), or the sign-up command
# `GH_WATCH=1 gh pr view <number or URL>` an agent runs for a pull request a
# subagent opened (see ../rules/AGENTS.md), it leaves a note for the gh-watch
# watcher in ~/.gemini/antigravity/gh-watch-inbox, which then starts watching
# that pull request for the conversation that ran the command. Only notes from
# the desktop app (a payload naming /.gemini/antigravity/) are kept: the CLI
# and the IDE keep their conversations elsewhere and a note from them would
# never be read.
#
# It must stay fast and must never fail: hooks run inside the agent's loop.
# It only ever answers `{}`, which changes nothing about the command or its
# permissions.
#
# The logic is in src/lib.rs; rust-hook.sh builds and runs it. If it cannot,
# it still answers `{}` and says why on stderr.

exec "$(dirname "$0")/rust-hook.sh" note_pr_create main.rs \
	'{}'
