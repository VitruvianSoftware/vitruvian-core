#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Tests for note-pr-create.sh, the hook that tells the watcher an agent has
# just opened a pull request.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNDER_TEST="${HERE}/note-pr-create.sh"
[ -f "${UNDER_TEST}" ] || UNDER_TEST="apps/desktop/antigravity/plugins/gh-watch/hooks/note-pr-create.sh"
[ -f "${UNDER_TEST}" ] || {
	echo "cannot find note-pr-create.sh" >&2
	exit 1
}

PASS=0
FAIL=0
check() {
	if [ "$2" = "0" ]; then
		printf '  PASS  %s\n' "$1"
		PASS=$((PASS + 1))
	else
		printf '  FAIL  %s\n' "$1"
		FAIL=$((FAIL + 1))
	fi
}

payload() { # command, transcript folder
	printf '{"conversationId":"c1","error":"","toolCall":{"args":{"CommandLine":"%s","Cwd":"/work"},"name":"run_command"},"transcriptPath":"/Users/x/.gemini/%s/brain/c1/t.jsonl"}' "$1" "$2"
}

# Runs the hook with a throwaway HOME; prints what it answered.
run_hook() {
	HOME="${SANDBOX}" sh "${UNDER_TEST}"
}
notes() { find "${SANDBOX}" -name '*.json' | wc -l | tr -d ' '; }

echo "note-pr-create_test:"

SANDBOX="$(mktemp -d)"
out=$(payload "ls -la" "antigravity" | run_hook)
[ "${out}" = "{}" ]
check "answers {} for an ordinary command" "$?"
[ "$(notes)" = "0" ]
check "leaves no note for an ordinary command" "$?"

out=$(payload "gh pr create --fill" "antigravity-cli" | run_hook)
[ "${out}" = "{}" ] && [ "$(notes)" = "0" ]
check "leaves no note outside the desktop app" "$?"

out=$(payload "gh pr create --fill" "antigravity" | run_hook)
[ "${out}" = "{}" ]
check "answers {} for gh pr create" "$?"
[ "$(notes)" = "1" ]
check "leaves one note for gh pr create in the desktop app" "$?"
note="$(find "${SANDBOX}" -name '*.json')"
case "${note}" in
*/.gemini/antigravity/gh-watch-inbox/*) inbox_ok=0 ;;
*) inbox_ok=1 ;;
esac
check "writes the note into the watcher's inbox" "${inbox_ok}"
grep -q '"CommandLine":"gh pr create --fill"' "${note}"
check "the note is the hook's own payload" "$?"
[ -z "$(find "${SANDBOX}" -name '*.tmp')" ]
check "leaves no half-written file behind" "$?"
rm -rf "${SANDBOX}"

# A HOME that cannot be written to must not make the hook fail.
SANDBOX="$(mktemp -d)"
out=$(payload "GH_WATCH=1 gh pr view 12 --json url --jq .url" "antigravity" | run_hook)
ok=1
[ "${out}" = "{}" ] && [ "$(notes)" = "1" ] && ok=0
check "leaves a note for the sign-up command" "${ok}"
rm -rf "${SANDBOX}"

SANDBOX="$(mktemp -d)"
out=$(payload "gh pr view 12 --json url" "antigravity" | run_hook)
ok=1
[ "${out}" = "{}" ] && [ "$(notes)" = "0" ] && ok=0
check "leaves no note for a plain gh pr view" "${ok}"
rm -rf "${SANDBOX}"

SANDBOX="/nonexistent/gh-watch-test"
out=$(payload "gh pr create" "antigravity" | run_hook)
rc=$?
[ "${rc}" = "0" ] && [ "${out}" = "{}" ]
check "still answers {} and exits 0 when it cannot write" "$?"

echo "${PASS} passed, ${FAIL} failed"
[ "${FAIL}" = "0" ]
