#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Each plugin is installed (and gh-watch exported) as its own folder, so the
# files every plugin shares are copied into each one rather than referenced.
# This keeps the copies identical: change one, change them all.
#
#   shared_files_test.sh <file>...   (from BUILD: every plugin's files)
#
# For each shared path below, every plugin's copy must match the first.

set -u

# Path inside a plugin, and how many copies must exist (0: any number).
shared="hooks/rust-hook.sh:9 hooks/rust-hook_test.sh:9 hooks/src/json.rs:0"

fails=0
for entry in $shared; do
	rel=${entry%:*}
	want=${entry##*:}
	first=
	n=0
	bad=0
	for f in "$@"; do
		case "$f" in */plugins/*/"$rel") ;; *) continue ;; esac
		n=$((n + 1))
		if [ -z "$first" ]; then
			first=$f
		elif ! cmp -s "$first" "$f"; then
			echo "FAIL $f differs from $first"
			bad=$((bad + 1))
		fi
	done
	if [ "$want" -ne 0 ] && [ "$n" -ne "$want" ]; then
		echo "FAIL $rel: $n copies, want one in each of the $want plugins"
		bad=$((bad + 1))
	fi
	[ "$bad" -eq 0 ] && echo "ok   $rel: $n identical copies"
	fails=$((fails + bad))
done

[ "$fails" -eq 0 ] || exit 1
echo "all copies identical"
