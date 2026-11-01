#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# PreToolUse (edit_file|write_file|run_command) and Stop hook (see
# ../hooks.json): scans what an edit or a shell command is about to write for
# dangerous constructs and hardcoded secrets, records findings for the Security
# Guidance panel, and answers {"decision":"ask"} (or "deny" for a critical
# finding) with the reasons, and {"decision":"allow"} otherwise (Antigravity
# denies a tool call whose PreToolUse hook answers without a decision).
#
# The logic is in src/lib.rs (handle_security_hook); rust-hook.sh builds and
# runs it. If it cannot, the answer below asks before every edit and command
# and says why: unchecked edits must not look checked.

exec "$(dirname "$0")/rust-hook.sh" security_check main.rs \
	'{"decision":"ask","reason":"security-guidance could not run its checks this time: its hook is still being built with rustc, or cannot be (details in ~/.cache/antigravity-plugins). Edits and commands are NOT being checked."}'
