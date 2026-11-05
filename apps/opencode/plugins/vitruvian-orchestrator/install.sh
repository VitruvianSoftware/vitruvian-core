#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -euo pipefail

PLUGIN_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_PLUGIN_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}/plugins/vitruvian-orchestrator"

mkdir -p "$USER_PLUGIN_DIR"

# OpenCode 2.2.5's ConfigPluginSource.scan checks that resolved entrypoints stay
# inside the plugin directory (Bun.resolveSync resolves symlinks before checking
# containment), so we write thin re-export loader files rather than a directory symlink.
cat >"$USER_PLUGIN_DIR/server.ts" <<EOF
export { default } from "$PLUGIN_SRC_DIR/server.mjs";
EOF

cat >"$USER_PLUGIN_DIR/tui.tsx" <<EOF
export { default } from "$PLUGIN_SRC_DIR/tui.tsx";
EOF

echo "Installed vitruvian-orchestrator user-level loaders into $USER_PLUGIN_DIR"
