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

resolve_bin() {
	local p="$1"
	if [ -z "$p" ]; then
		echo ""
	elif [[ "$p" = /* ]]; then
		echo "$p"
	else
		echo "$PWD/$p"
	fi
}

HOOK="$(resolve_bin "${1:-apps/desktop/antigravity/plugins/live-context/hooks/verify-response-shape.sh}")"
REF_HOOK="$(resolve_bin "${2:-}")"
PLUGIN_DIR="$PWD/apps/desktop/antigravity/plugins/live-context"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

run_case() {
	local name="$1"
	local settings_json="$2"
	local input_json="$3"

	local dir_sut="$TMP/${name}_sut"
	local state_sut="$dir_sut/live-context-state"
	mkdir -p "$state_sut"
	if [ -n "$settings_json" ]; then
		printf '%s' "$settings_json" >"$state_sut/settings.json"
	fi

	local out_sut
	out_sut="$(cd "$PLUGIN_DIR" && printf '%s' "$input_json" | HOME="$dir_sut" ANTIGRAVITY_APP_DATA_DIR="$dir_sut" STATE_DIR="$state_sut" "$HOOK")"

	if [ -n "$REF_HOOK" ]; then
		local dir_ref="$TMP/${name}_ref"
		local state_ref="$dir_ref/live-context-state"
		mkdir -p "$state_ref"
		if [ -n "$settings_json" ]; then
			printf '%s' "$settings_json" >"$state_ref/settings.json"
		fi

		local out_ref
		out_ref="$(cd "$PLUGIN_DIR" && printf '%s' "$input_json" | HOME="$dir_ref" ANTIGRAVITY_APP_DATA_DIR="$dir_ref" STATE_DIR="$state_ref" "$REF_HOOK")"

		if [ "$out_sut" != "$out_ref" ]; then
			echo "FAIL [$name]: parity stdout mismatch:" >&2
			echo "SUT: $out_sut" >&2
			echo "REF: $out_ref" >&2
			exit 1
		fi

		if [ -f "$state_sut/verdicts.jsonl" ] || [ -f "$state_ref/verdicts.jsonl" ]; then
			local v_sut v_ref
			v_sut="$(sed -E 's/"ts":"[^"]+"/"ts":"0"/g' "$state_sut/verdicts.jsonl")"
			v_ref="$(sed -E 's/"ts":"[^"]+"/"ts":"0"/g' "$state_ref/verdicts.jsonl")"
			if [ "$v_sut" != "$v_ref" ]; then
				echo "FAIL [$name]: parity verdicts.jsonl mismatch:" >&2
				echo "SUT: $v_sut" >&2
				echo "REF: $v_ref" >&2
				exit 1
			fi
		fi
	fi

	printf '%s' "$out_sut"
}

LONG_BODY="Here is a detailed explanation of the root cause and how we resolved the issue across the build pipeline. We verified every target and confirmed that all unit and integration checks pass without regressions. Detailed breakdown of the changes and test coverage follows below in the summary list so the team can review everything clearly."

# 1. Invalid JSON -> allow
out="$(run_case "invalid_json" "" "not-json")"
[ "$out" = '{"decision":"allow"}' ] || {
	echo "FAIL invalid_json: $out" >&2
	exit 1
}

# 2. Short reply (exempt) -> allow
out="$(run_case "short_exempt" '{"mode":"enforce"}' '{"conversationId":"abcdef123456","lastAssistantMessage":"Done."}')"
[ "$out" = '{"decision":"allow"}' ] || {
	echo "FAIL short_exempt: $out" >&2
	exit 1
}

# 3. Substantive clean reply in enforce mode -> allow + pass verdict
out="$(run_case "clean_enforce" '{"mode":"enforce"}' "{\"conversationId\":\"abcdef123456\",\"lastAssistantMessage\":\"${LONG_BODY}\"}")"
[ "$out" = '{"decision":"allow"}' ] || {
	echo "FAIL clean_enforce: $out" >&2
	exit 1
}

# 4. Substantive reply with filler closing in enforce mode -> continue
out="$(run_case "filler_enforce" '{"mode":"enforce"}' "{\"conversationId\":\"abcdef123456\",\"lastAssistantMessage\":\"${LONG_BODY}\\nNothing needed from you.\"}")"
case "$out" in
*'"decision":"continue"'*'"RESPONSE CONTRACT: closes with an empty '\''nothing needed'\'' line'*) ;;
*)
	echo "FAIL filler_enforce: $out" >&2
	exit 1
	;;
esac

# 5. Substantive reply with filler closing in log mode -> allow
out="$(run_case "filler_log" '{"mode":"log"}' "{\"conversationId\":\"abcdef123456\",\"lastAssistantMessage\":\"${LONG_BODY}\\nNothing needed from you.\"}")"
[ "$out" = '{"decision":"allow"}' ] || {
	echo "FAIL filler_log: $out" >&2
	exit 1
}

echo "PASS"
