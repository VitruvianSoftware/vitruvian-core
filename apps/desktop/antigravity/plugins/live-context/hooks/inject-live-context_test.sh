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

HOOK="$(resolve_bin "${1:-apps/desktop/antigravity/plugins/live-context/hooks/inject-live-context.sh}")"
REF_HOOK="$(resolve_bin "${2:-}")"
PLUGIN_DIR="$PWD/apps/desktop/antigravity/plugins/live-context"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

run_case() {
	local name="$1"
	local settings_json="$2"
	local snapshot_json="$3"

	local dir_sut="$TMP/${name}_sut"
	local state_sut="$dir_sut/live-context-state"
	mkdir -p "$state_sut"
	if [ -n "$settings_json" ]; then
		printf '%s' "$settings_json" >"$state_sut/settings.json"
	fi
	if [ -n "$snapshot_json" ]; then
		printf '%s' "$snapshot_json" >"$state_sut/snapshot.json"
	fi

	local out_sut
	out_sut="$(cd "$PLUGIN_DIR" && printf '{}' | HOME="$dir_sut" ANTIGRAVITY_APP_DATA_DIR="$dir_sut" STATE_DIR="$state_sut" "$HOOK")"

	if [ -n "$REF_HOOK" ]; then
		local dir_ref="$TMP/${name}_ref"
		local state_ref="$dir_ref/live-context-state"
		mkdir -p "$state_ref"
		if [ -n "$settings_json" ]; then
			printf '%s' "$settings_json" >"$state_ref/settings.json"
		fi
		if [ -n "$snapshot_json" ]; then
			printf '%s' "$snapshot_json" >"$state_ref/snapshot.json"
		fi

		local out_ref
		out_ref="$(cd "$PLUGIN_DIR" && printf '{}' | HOME="$dir_ref" ANTIGRAVITY_APP_DATA_DIR="$dir_ref" STATE_DIR="$state_ref" "$REF_HOOK")"

		if [ "$out_sut" != "$out_ref" ]; then
			echo "FAIL [$name]: parity stdout mismatch:" >&2
			echo "SUT: $out_sut" >&2
			echo "REF: $out_ref" >&2
			exit 1
		fi
	fi

	printf '%s' "$out_sut"
}

# 1. Default state (empty state dir) injects default contract and empty GitHub block
out="$(run_case "default_empty" "" "")"
case "$out" in
*'"injectSteps"'*'RESPONSE CONTRACT: Scale to the question.'*) ;;
*)
	echo "FAIL default_empty: $out" >&2
	exit 1
	;;
esac

# 2. Full git + github snapshot
out="$(run_case "full_snapshot" \
	'{"injectGit":true,"injectGitHub":true,"injectContract":true}' \
	'{"git":{"branch":"feat/hooks","headSha":"1234abc","dirtyCount":1,"dirtyFiles":["BUILD"]},"github":{"repo":"VitruvianSoftware/vitruvian-core","openPrs":[{"number":10,"title":"Test PR","isDraft":false}],"mergedPrs":[],"openIssues":2}}')"
case "$out" in
*'LIVE GIT WORKSPACE: branch feat/hooks (1234abc)'*'1 uncommitted file: BUILD'*'#10 Test PR'*'OPEN issues: 2'*) ;;
*)
	echo "FAIL full_snapshot: $out" >&2
	exit 1
	;;
esac

# 3. All injections disabled -> {}
out="$(run_case "all_disabled" \
	'{"injectGit":false,"injectGitHub":false,"injectContract":false}' \
	'{}')"
[ "$out" = "{}" ] || {
	echo "FAIL all_disabled: $out" >&2
	exit 1
}

echo "PASS"
