#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# PostToolUse hook on run_command (see ../hooks.json). When an agent ran an
# `agy plugin` command, it saves the payload as a note in
# ${ANTIGRAVITY_APP_DATA_DIR:-~/.gemini/antigravity}/ext-marketplace-inbox, so
# the Extensions Marketplace sidecar knows a plugin was installed, toggled or
# removed from the CLI. It always answers {}.
#
# The logic is in src/lib.rs (run_from_stdio); rust-hook.sh builds and runs
# it. If it cannot, the hook answers {} and stderr says why.

exec "$(dirname "$0")/rust-hook.sh" note_plugin_cmd main.rs \
	'{}'
