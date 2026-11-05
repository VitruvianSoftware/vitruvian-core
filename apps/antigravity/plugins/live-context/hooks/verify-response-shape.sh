#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Stop hook (see ../hooks.json): checks the reply at the end of a turn against
# the response contract, logs the verdict to verdicts.jsonl and, in "enforce"
# mode, bounces it once ({"decision":"continue"}) when it closes with an empty
# "nothing needed" line.
#
# The logic is in src/lib.rs (run_verify_response_shape); rust-hook.sh builds
# and runs it. If it cannot, the turn is allowed to end and stderr says why.

exec "$(dirname "$0")/rust-hook.sh" live_context_hooks bin/verify_response_shape.rs \
	'{"decision":"allow"}'
