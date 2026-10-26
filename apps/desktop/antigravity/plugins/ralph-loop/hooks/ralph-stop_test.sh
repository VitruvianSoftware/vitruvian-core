#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

set -euo pipefail

if [ -n "${VITRUVIAN_NODE:-}" ]; then
	node_rel="${VITRUVIAN_NODE#external/}"
	for cand in "$PWD/$VITRUVIAN_NODE" "$(dirname "$PWD")/$node_rel" "${RUNFILES_DIR:-}/$node_rel"; do
		if [ -x "$cand" ]; then
			export PATH="$(dirname "$cand"):$PATH"
			break
		fi
	done
fi

HOOK="${1:-apps/desktop/antigravity/plugins/ralph-loop/hooks/ralph-stop.sh}"
REF_HOOK="${2:-}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

run_case() {
	local name="$1"
	local initial_state="$2"
	local conv_id="$3"
	local input="$4"

	local dir_sut="$TMP/${name}_sut"
	local state_dir_sut="$dir_sut/ralph-loop-state"
	mkdir -p "$state_dir_sut"
	if [ -n "$initial_state" ]; then
		printf '%s' "$initial_state" >"$state_dir_sut/${conv_id}.json"
	fi

	local out_sut
	out_sut="$(printf '%s' "$input" | HOME="$dir_sut" ANTIGRAVITY_APP_DATA_DIR="$dir_sut" "$HOOK")"

	if [ -n "$REF_HOOK" ]; then
		local dir_ref="$TMP/${name}_ref"
		local state_dir_ref="$dir_ref/ralph-loop-state"
		mkdir -p "$state_dir_ref"
		if [ -n "$initial_state" ]; then
			printf '%s' "$initial_state" >"$state_dir_ref/${conv_id}.json"
		fi

		local out_ref
		out_ref="$(printf '%s' "$input" | HOME="$dir_ref" ANTIGRAVITY_APP_DATA_DIR="$dir_ref" "$REF_HOOK")"

		if [ "$out_sut" != "$out_ref" ]; then
			echo "FAIL [$name]: parity stdout mismatch: sut='$out_sut' ref='$out_ref'" >&2
			exit 1
		fi

		if [ -n "$initial_state" ]; then
			local state_sut state_ref
			state_sut="$(node -e 'const fs=require("fs");const o=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));delete o.updatedAt;delete o.completedAt;const s=Object.keys(o).sort().reduce((a,k)=>(a[k]=o[k],a),{});console.log(JSON.stringify(s));' "$state_dir_sut/${conv_id}.json")"
			state_ref="$(node -e 'const fs=require("fs");const o=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));delete o.updatedAt;delete o.completedAt;const s=Object.keys(o).sort().reduce((a,k)=>(a[k]=o[k],a),{});console.log(JSON.stringify(s));' "$state_dir_ref/${conv_id}.json")"
			if [ "$state_sut" != "$state_ref" ]; then
				echo "FAIL [$name]: parity state mismatch:" >&2
				echo "SUT: $state_sut" >&2
				echo "REF: $state_ref" >&2
				exit 1
			fi
		fi
	fi

	printf '%s' "$out_sut"
}

# 1. Empty payload -> {}
out="$(run_case "empty" "" "conv-0" "")"
[ "$out" = "{}" ] || {
	echo "FAIL empty: $out" >&2
	exit 1
}

# 2. Active loop continues and increments iteration
out="$(run_case "continue_loop" \
	'{"conversationId":"conv-1","prompt":"Fix lint","completionPromise":"DONE","iteration":1,"maxIterations":4,"active":true,"status":"running"}' \
	"conv-1" \
	'{"conversationId":"conv-1","lastAssistantMessage":"Working on lint..."}')"
case "$out" in
*'"decision":"continue"'*'"Ralph Loop (iteration 2/4): continue working on the task until completion criteria are met and emit <promise>DONE</promise>. Task: Fix lint"'*) ;;
*)
	echo "FAIL continue_loop: $out" >&2
	exit 1
	;;
esac

# 3. Active loop completes when promise tag is matched
out="$(run_case "complete_loop" \
	'{"conversationId":"conv-2","prompt":"Fix lint","completionPromise":"DONE","iteration":2,"maxIterations":4,"active":true,"status":"running"}' \
	"conv-2" \
	'{"conversationId":"conv-2","lastAssistantMessage":"All done! <promise>DONE</promise>"}')"
[ "$out" = "{}" ] || {
	echo "FAIL complete_loop: $out" >&2
	exit 1
}

# 4. Active loop stops at maxIterations
out="$(run_case "max_iter" \
	'{"conversationId":"conv-3","prompt":"Fix lint","completionPromise":"DONE","iteration":4,"maxIterations":4,"active":true,"status":"running"}' \
	"conv-3" \
	'{"conversationId":"conv-3","lastAssistantMessage":"Still working"}')"
[ "$out" = "{}" ] || {
	echo "FAIL max_iter: $out" >&2
	exit 1
}

# 5. Inactive loop returns {}
out="$(run_case "inactive" \
	'{"conversationId":"conv-4","completionPromise":"DONE","iteration":1,"maxIterations":4,"active":false,"status":"completed"}' \
	"conv-4" \
	'{"conversationId":"conv-4","lastAssistantMessage":"Hello"}')"
[ "$out" = "{}" ] || {
	echo "FAIL inactive: $out" >&2
	exit 1
}

echo "PASS"
