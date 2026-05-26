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

set -e

# Locate the prettier binary in the runfiles
# It is expected to be in the same directory as this script (in runfiles)
DIR="$(dirname "$0")"

# The target name is "prettier_bin", so the binary should be named "prettier_bin"
# However, aspect_rules_js might put it in a subdirectory or give it a different name structure in runfiles.
# Based on observation, it is in "prettier_bin_/prettier_bin".

PRETTIER_BIN="$DIR/prettier_bin_/prettier_bin"

if [[ ! -f "$PRETTIER_BIN" ]]; then
	# Fallback: try to find it in the current directory
	FOUND=$(find "$DIR" -name "prettier_bin" -type f | head -n 1)
	if [[ -n "$FOUND" ]]; then
		PRETTIER_BIN="$FOUND"
	else
		echo "ERROR: Could not find prettier_bin in $DIR" >&2
		exit 1
	fi
fi

ARGS=()
for arg in "$@"; do
	if [[ -L "$arg" ]]; then
		# Skip symlinks to avoid Prettier errors
		continue
	fi
	ARGS+=("$arg")
done

exec "$PRETTIER_BIN" "${ARGS[@]}"
