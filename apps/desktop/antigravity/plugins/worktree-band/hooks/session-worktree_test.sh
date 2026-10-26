#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

set -euo pipefail

HOOK="${1:-apps/desktop/antigravity/plugins/worktree-band/hooks/session-worktree.sh}"
REF_HOOK="${2:-}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

count_notes() {
	local dir="$1"
	if [ ! -d "$dir" ]; then
		echo 0
		return
	fi
	find "$dir" -maxdepth 1 -name '*.json' | wc -l | tr -d ' '
}

first_note_content() {
	local dir="$1"
	local f
	f="$(find "$dir" -maxdepth 1 -name '*.json' | head -n 1)"
	if [ -n "$f" ]; then
		cat "$f"
	fi
}

run_case() {
	local name="$1"
	local input="$2"
	local expect_count="$3"

	local home_sut="$TMP/${name}_sut"
	mkdir -p "$home_sut"
	local out_sut
	out_sut="$(printf '%s' "$input" | HOME="$home_sut" "$HOOK")"

	if [ "$out_sut" != "{}" ]; then
		echo "FAIL [$name]: expected stdout '{}', got '$out_sut'" >&2
		exit 1
	fi

	local inbox_sut="$home_sut/.gemini/antigravity/worktree-band-inbox"
	local count_sut
	count_sut="$(count_notes "$inbox_sut")"
	if [ "$count_sut" != "$expect_count" ]; then
		echo "FAIL [$name]: expected $expect_count notes, got $count_sut" >&2
		exit 1
	fi

	if [ "$expect_count" -gt 0 ]; then
		local content_sut
		content_sut="$(first_note_content "$inbox_sut")"
		if [ "$content_sut" != "$input" ]; then
			echo "FAIL [$name]: note content mismatch" >&2
			exit 1
		fi
	fi

	if [ -n "$REF_HOOK" ]; then
		local home_ref="$TMP/${name}_ref"
		mkdir -p "$home_ref"
		local out_ref
		out_ref="$(printf '%s' "$input" | HOME="$home_ref" "$REF_HOOK")"
		local inbox_ref="$home_ref/.gemini/antigravity/worktree-band-inbox"
		local count_ref
		count_ref="$(count_notes "$inbox_ref")"

		if [ "$out_sut" != "$out_ref" ]; then
			echo "FAIL [$name]: parity stdout mismatch: sut='$out_sut' ref='$out_ref'" >&2
			exit 1
		fi
		if [ "$count_sut" != "$count_ref" ]; then
			echo "FAIL [$name]: parity note count mismatch: sut=$count_sut ref=$count_ref" >&2
			exit 1
		fi
		if [ "$expect_count" -gt 0 ]; then
			local content_ref
			content_ref="$(first_note_content "$inbox_ref")"
			if [ "$content_sut" != "$content_ref" ]; then
				echo "FAIL [$name]: parity note content mismatch" >&2
				exit 1
			fi
		fi
	fi
}

run_case "workspace_paths" '{"workspacePaths":["/repo/wt"]}' 1
run_case "cwd_key" '{"cwd":"/repo/wt"}' 1
run_case "conversation_id" '{"conversationId":"conv-42"}' 1
run_case "unrelated_json" '{"tool_name":"view_file"}' 0
run_case "empty_payload" '' 0

echo "PASS"
