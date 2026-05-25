#!/usr/bin/env bash
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
