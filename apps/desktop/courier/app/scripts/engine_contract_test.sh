#!/bin/bash
# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# What the app assumes about its engine, checked against the engine itself, on any platform:
#   - the flags EngineSupervisor.swift starts it with are the ones its usage line names,
#   - the protocol number Protocol.swift speaks is protocol.json's.
#
# It is also why the courier-app-macos unit runs when only the engine or the protocol changes: every other test of
# the app is macOS-only and `manual`, and the presubmit planner selects a unit only for a change in its own
# package or for a non-manual test in it that depends on the change.
#
# Usage: engine_contract_test.sh <courier-engine> <EngineSupervisor.swift> <Protocol.swift> <the protocol's files>...
# (protocol.json among the last, in any order).
set -euo pipefail

engine="${1:?engine}"
supervisor="${2:?EngineSupervisor.swift}"
swift_protocol="${3:?Protocol.swift}"
shift 3
protocol_json=""
for path in "$@"; do
	case "$path" in
	*/protocol.json) protocol_json="$path" ;;
	esac
done
if [ -z "$protocol_json" ]; then
	echo "FAIL: no protocol.json among: $*" >&2
	exit 2
fi
failed=0

# The arguments the supervisor passes, as written in its source.
if grep -q '"--data", dataDir.path, "--parent-fd", "0"' "$supervisor"; then
	echo "ok: the supervisor starts the engine with --data DIR --parent-fd 0"
else
	echo "FAIL: EngineSupervisor.swift no longer passes --data DIR --parent-fd 0; update this test with it" >&2
	failed=1
fi

set +e
usage="$("$engine" --help 2>&1)"
status=$?
set -e
if [ "$status" -eq 2 ] && [[ "$usage" == *"--data DIR"* ]] && [[ "$usage" == *"--parent-fd N"* ]]; then
	echo "ok: the engine takes --data DIR and --parent-fd N"
else
	echo "FAIL: the engine's usage (exit $status) does not name --data DIR and --parent-fd N: $usage" >&2
	failed=1
fi

# protocol.json's top-level "protocol": N (the first such key; the file has no other).
want="$(sed -n 's/^  "protocol": \([0-9][0-9]*\),$/\1/p' "$protocol_json" | head -1)"
got="$(sed -n 's/^ *public static let version = \([0-9][0-9]*\)$/\1/p' "$swift_protocol" | head -1)"
if [ -n "$want" ] && [ "$want" = "$got" ]; then
	echo "ok: Protocol.swift speaks protocol $got, as protocol.json says"
else
	echo "FAIL: Protocol.swift speaks protocol '${got}', protocol.json says '${want}'" >&2
	failed=1
fi

exit "$failed"
