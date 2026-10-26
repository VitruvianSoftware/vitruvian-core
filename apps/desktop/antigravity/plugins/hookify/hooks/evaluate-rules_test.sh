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

HOOK="${1:-apps/desktop/antigravity/plugins/hookify/hooks/evaluate-rules.sh}"
REF_HOOK="${2:-}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

setup_workspace() {
	local ws="$1"
	mkdir -p "$ws/.agents"
	cat >"$ws/.agents/hookify.block-rm-rf.md" <<'EOF'
---
name: block-rm-rf
enabled: true
event: bash
tool: run_command
action: block
conditions:
  - field: CommandLine
    operator: regex_match
    pattern: "rm\\s+-rf\\s+/"
---
Do not run destructive rm -rf / commands.
EOF

	cat >"$ws/.agents/hookify.rewrite-npm.md" <<'EOF'
---
name: rewrite-npm
enabled: true
event: bash
tool: run_command
action: overwrite
conditions:
  - field: CommandLine
    operator: starts_with
    pattern: "npm test"
overwrite:
  field: CommandLine
  find: "^npm test"
  replace: "bazel test //..."
---
Use bazel test instead of npm test.
EOF

	cat >"$ws/.agents/hookify.stop-hygiene.md" <<'EOF'
---
name: stop-hygiene
enabled: true
event: Stop
action: block
conditions:
  - field: reason
    operator: not_contains
    pattern: "worktree hygiene"
---
State worktree hygiene before stopping.
EOF
}

run_case() {
	local name="$1"
	local input_template="$2"

	local dir_sut="$TMP/${name}_sut"
	local ws_sut="$dir_sut/ws"
	mkdir -p "$dir_sut" "$ws_sut"
	setup_workspace "$ws_sut"

	local input_sut="${input_template//__CWD__/$ws_sut}"
	local out_sut
	out_sut="$(printf '%s' "$input_sut" | HOME="$dir_sut" ANTIGRAVITY_APP_DATA_DIR="$dir_sut" "$HOOK")"

	if [ -n "$REF_HOOK" ]; then
		local dir_ref="$TMP/${name}_ref"
		local ws_ref="$dir_ref/ws"
		mkdir -p "$dir_ref" "$ws_ref"
		setup_workspace "$ws_ref"

		local input_ref="${input_template//__CWD__/$ws_ref}"
		local out_ref
		out_ref="$(printf '%s' "$input_ref" | HOME="$dir_ref" ANTIGRAVITY_APP_DATA_DIR="$dir_ref" "$REF_HOOK")"

		if [ "$out_sut" != "$out_ref" ]; then
			echo "FAIL [$name]: parity stdout mismatch:" >&2
			echo "SUT: $out_sut" >&2
			echo "REF: $out_ref" >&2
			exit 1
		fi

		if [ -f "$dir_sut/hookify-events.json" ] || [ -f "$dir_ref/hookify-events.json" ]; then
			local ev_sut ev_ref
			ev_sut="$(sed -E -e 's/"id": "[^"]+"/"id": "0"/g' -e 's/"timestamp": [0-9]+/"timestamp": 0/g' "$dir_sut/hookify-events.json")"
			ev_ref="$(sed -E -e 's/"id": "[^"]+"/"id": "0"/g' -e 's/"timestamp": [0-9]+/"timestamp": 0/g' "$dir_ref/hookify-events.json")"
			if [ "$ev_sut" != "$ev_ref" ]; then
				echo "FAIL [$name]: parity events mismatch:" >&2
				echo "SUT: $ev_sut" >&2
				echo "REF: $ev_ref" >&2
				exit 1
			fi
		fi
	fi

	printf '%s' "$out_sut"
}

# 1. Empty input -> {}
out="$(run_case "empty" "")"
[ "$out" = "{}" ] || {
	echo "FAIL empty: $out" >&2
	exit 1
}

# 2. PreToolUse allow (no matching rule) -> {}
out="$(run_case "allow_cmd" '{"cwd":"__CWD__","toolCall":{"name":"run_command","args":{"CommandLine":"bazel build //..."}}}')"
[ "$out" = "{}" ] || {
	echo "FAIL allow_cmd: $out" >&2
	exit 1
}

# 3. PreToolUse block -> deny
out="$(run_case "block_rm" '{"cwd":"__CWD__","toolCall":{"name":"run_command","args":{"CommandLine":"rm -rf /tmp/foo"}}}')"
case "$out" in
*'"permissionDecision":"deny"'*'block-rm-rf'*) ;;
*)
	echo "FAIL block_rm: $out" >&2
	exit 1
	;;
esac

# 4. PreToolUse overwrite -> allow with updatedInput
out="$(run_case "overwrite_npm" '{"cwd":"__CWD__","toolCall":{"name":"run_command","args":{"CommandLine":"npm test --watch"}}}')"
case "$out" in
*'"permissionDecision":"allow"'*'"CommandLine":"bazel test //... --watch"'*) ;;
*)
	echo "FAIL overwrite_npm: $out" >&2
	exit 1
	;;
esac

# 5. Stop block -> continue: false
out="$(run_case "stop_block" '{"cwd":"__CWD__","hook_event_name":"Stop","reason":"Finished task."}')"
case "$out" in
*'"continue":false'*'"decision":"block"'*) ;;
*)
	echo "FAIL stop_block: $out" >&2
	exit 1
	;;
esac

# 6. Stop allow -> {}
out="$(run_case "stop_allow" '{"cwd":"__CWD__","hook_event_name":"Stop","reason":"Finished task. Verified worktree hygiene."}')"
[ "$out" = "{}" ] || {
	echo "FAIL stop_allow: $out" >&2
	exit 1
}

echo "PASS"
