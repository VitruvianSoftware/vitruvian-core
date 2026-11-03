#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# PreInvocation hook: records the user's hard constraints and pins them, with
# matching library lessons, right before the turn.
# The logic is in ../lib/runtime_hooks.py (standard-library Python 3.9+).
# Always prints one JSON answer and exits 0; if Python is missing or fails
# it answers the fallback below and the error goes to
# ~/.gemini/antigravity/harness2/hooks.log.

fallback='{}'
dir=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd) || { printf '%s\n' "$fallback"; exit 0; }
log="${HARNESS2_HOME:-$HOME/.gemini/antigravity/harness2}/hooks.log"
mkdir -p "$(dirname "$log")" 2>/dev/null
py=$(command -v python3 2>/dev/null || echo /usr/bin/python3)
out=$("$py" "$dir/lib/runtime_hooks.py" pre-invocation 2>>"$log")
case $out in
'{'*) printf '%s\n' "$out" ;;
*) printf '%s\n' "$fallback" ;;
esac
exit 0
