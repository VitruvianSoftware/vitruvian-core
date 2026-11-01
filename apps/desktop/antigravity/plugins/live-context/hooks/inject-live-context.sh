#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# PreInvocation hook (see ../hooks.json): tells the model the live Git state of
# the conversation's workspace, the open and recently merged PRs, and the
# response contract, as {"injectSteps":[{"ephemeralMessage":"..."}]}.
#
# The logic is in src/lib.rs (run_inject_live_context); rust-hook.sh builds and
# runs it. If it cannot, the message below says the state is unknown.

exec "$(dirname "$0")/rust-hook.sh" live_context_hooks bin/inject_live_context.rs \
	'{"injectSteps":[{"ephemeralMessage":"live-context did not run this turn: its hook is still being built with rustc, or cannot be (details in ~/.cache/antigravity-plugins). Live Git and GitHub state is UNKNOWN: do not state branch, PR or issue status without querying it first."}]}'
