#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Antigravity runs this hook after `invoke_subagent` or `send_message` tool calls
# (see ../hooks.json). It writes an atomic event note into
# ~/.gemini/antigravity/savvy-fleet-inbox/ (or $ANTIGRAVITY_APP_DATA_DIR) so
# the savvy-fleet sidecar panel can immediately display subagent launches,
# roles, tiers, and messages alongside live transcript inspection.
#
# It must stay fast and never fail: hooks run inside the agent's loop and only
# output `{}`.
#
# The logic is in src/lib.rs; rust-hook.sh builds and runs it. If it cannot,
# it still answers `{}` and says why on stderr.

exec "$(dirname "$0")/rust-hook.sh" track_subagent main.rs \
	'{}'
