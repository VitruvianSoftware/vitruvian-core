#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# PostInvocation hook (see ../hooks.json). When the payload carries a
# "conversationId", it saves the payload as a note in
# ${ANTIGRAVITY_APP_DATA_DIR:-~/.gemini/antigravity}/receipts-report-inbox, so
# the receipts-report sidecar can index active conversations without walking
# every directory on each poll. It always answers {}.
#
# The logic is in src/lib.rs (run_from_stdio); rust-hook.sh builds and runs
# it. If it cannot, the hook answers {} and stderr says why.

exec "$(dirname "$0")/rust-hook.sh" record_turn main.rs \
	'{}'
