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
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Runs the plugin's behaviour tests (hooks/*.test.tsx) with the pinned Claude
# Code CLI. They need no login and no network.
set -euo pipefail

claude="$PWD/$1"
plugin_dir="apps/claude-code/plugins/vitruvian-orchestrator"

# Bazel's runfiles are symlinks. Copy real files so the CLI sees a normal plugin.
# Keep the folder name: some tests match paths ending in /vitruvian-orchestrator/agents/.
work="$TEST_TMPDIR/vitruvian-orchestrator"
mkdir -p "$work" "$TEST_TMPDIR/home"
cp -RL "$plugin_dir/." "$work/"

status=0
output="$(cd "$work" && HOME="$TEST_TMPDIR/home" TMPDIR="$TEST_TMPDIR" \
	DISABLE_AUTOUPDATER=1 "$claude" plugin test . 2>&1)" || status=$?
printf '%s\n' "$output"

if [ "$status" -ne 0 ]; then
	echo "FAIL: claude plugin test exited $status" >&2
	exit 1
fi

# A run that finds no tests must not count as a pass.
passed="$(printf '%s\n' "$output" | sed -nE 's/^ *([0-9]+) pass$/\1/p' | tail -1)"
if [ -z "$passed" ] || [ "$passed" -eq 0 ]; then
	echo "FAIL: no plugin tests ran" >&2
	exit 1
fi
