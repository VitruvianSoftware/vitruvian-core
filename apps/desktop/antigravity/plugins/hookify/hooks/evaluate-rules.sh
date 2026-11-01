#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# PreToolUse and Stop hook (see ../hooks.json): loads the rules in
# ~/.gemini/antigravity/hookify-rules.json and the workspace's
# .agents/hookify.*.md, evaluates them against the payload, records matches in
# hookify-events.json, and prints the decision as JSON.
#
# The logic is in src/lib.rs (handle_hookify_payload); rust-hook.sh builds and
# runs it. If it cannot, the fallback below asks before every tool call and
# says the rules are not being enforced.

exec "$(dirname "$0")/rust-hook.sh" evaluate_rules main.rs \
	'{"decision":"ask","reason":"hookify could not run its rules this time: its hook is still being built with rustc, or cannot be (details in ~/.cache/antigravity-plugins). Its rules are NOT being enforced."}'
