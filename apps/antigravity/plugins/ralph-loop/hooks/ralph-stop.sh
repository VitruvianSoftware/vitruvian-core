#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Stop hook (see ../hooks.json). When this conversation has an active loop in
# ~/.gemini/antigravity/ralph-loop-state/<conversationId>.json and the reply
# does not contain <promise>COMPLETION_PROMISE</promise>, it counts the
# iteration and answers {"decision":"continue","reason":"Ralph Loop (iteration
# N/M): ..."}; at the promise or at maxIterations it ends the loop and
# answers {}.
#
# The logic is in src/lib.rs (handle_stop_payload); rust-hook.sh builds and
# runs it. If it cannot, the turn is allowed to end (never "continue", which
# could loop forever) and stderr says why.

exec "$(dirname "$0")/rust-hook.sh" ralph_stop main.rs \
	'{"decision":"allow"}'
