#!/bin/sh
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

# A tiny stand-in for desktop-commander, for bridge.rs's tests. Run as the
# "node": `fake_mcp.sh --version` prints a Node version; `fake_mcp.sh DIR`
# serves MCP over stdin/stdout. DIR is the test's own folder: the fake writes
# its pid to DIR/fake.pid and a started child's pid to DIR/sleep.pid. If
# DIR/stubborn exists it ignores SIGTERM and the end of its input. If
# DIR/slow_init exists it waits 3 s before answering `initialize`; if
# DIR/hang_init exists it never answers it. Every start appends a line to
# DIR/spawns.
#
# Tools (by name in tools/call):
#   echo         answers "ok" at once
#   notify       sends a notifications/message, then answers "after note"
#   hang         starts `sleep 30` and never answers
#   spawn        starts `sleep 30` in the background and answers at once
#   big          answers ~3 MB of text that is all `"` and line breaks
#   exit         exits without answering
#   fail         answers with a JSON-RPC error
#   huge         answers with one 64 MiB line, its id last (as the MCP SDK
#                orders a result: result, jsonrpc, id)
#   huge_noid    writes one 64 MiB line with no id, then nothing
#   huge_late    waits 2 s, then answers like huge

if [ "${1:-}" = "--version" ]; then
	echo "v22.12.0"
	exit 0
fi

dir="$1"
echo $$ >"$dir/fake.pid"
echo $$ >>"$dir/spawns"
if [ -e "$dir/stubborn" ]; then
	trap '' TERM
fi

reply() {
	printf '{"jsonrpc":"2.0","id":%s,"result":%s}\n' "$1" "$2"
}

text() {
	printf '{"content":[{"type":"text","text":"%s"}]}' "$1"
}

while IFS= read -r line; do
	id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
	method=$(printf '%s' "$line" | sed -n 's/.*"method":"\([^"]*\)".*/\1/p')
	case "$method" in
	initialize)
		if [ -e "$dir/slow_init" ]; then sleep 3; fi
		if [ -e "$dir/hang_init" ]; then
			sleep 300 &
			echo $! >"$dir/init_sleep.pid"
			wait
		fi
		reply "$id" '{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"fake","version":"0"}}'
		printf '{"jsonrpc":"2.0","method":"notifications/message","params":{"level":"info","data":"fake started"}}\n'
		;;
	tools/list)
		reply "$id" "{\"tools\":[{\"name\":\"echo\",\"description\":\"env $DESKTOP_COMMANDER_DISABLE_TELEMETRY $DC_FLAG_URL\",\"inputSchema\":{\"type\":\"object\"}},{\"name\":\"set_config_value\",\"description\":\"\",\"inputSchema\":{\"type\":\"object\"}},{\"name\":\"start_process\",\"description\":\"\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"command\":{\"type\":\"string\"}}}}]}"
		;;
	tools/call)
		name=$(printf '%s' "$line" | sed -n 's/.*"params":{[^}]*"name":"\([^"]*\)".*/\1/p')
		[ -n "$name" ] || name=$(printf '%s' "$line" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')
		case "$name" in
		echo) reply "$id" "$(text ok)" ;;
		notify)
			printf '{"jsonrpc":"2.0","method":"notifications/message","params":{"level":"info","data":"working on it"}}\n'
			reply "$id" "$(text 'after note')"
			;;
		hang)
			sleep 30 &
			echo $! >"$dir/sleep.pid"
			;;
		spawn)
			sleep 30 &
			echo $! >"$dir/sleep.pid"
			reply "$id" "$(text spawned)"
			;;
		big)
			body=$(head -c 1500000 /dev/zero | tr '\0' 'q' | sed 's/q/\\"\\n/g')
			reply "$id" "$(text "$body")"
			;;
		huge)
			printf '{"result":{"content":[{"type":"text","text":"'
			head -c 67108864 /dev/zero | tr '\0' 'q'
			printf '"}]},"jsonrpc":"2.0","id":%s}\n' "$id"
			;;
		huge_late)
			sleep 2
			printf '{"result":{"content":[{"type":"text","text":"'
			head -c 67108864 /dev/zero | tr '\0' 'q'
			printf '"}]},"jsonrpc":"2.0","id":%s}\n' "$id"
			;;
		huge_noid)
			printf '{"result":{"content":[{"type":"text","text":"'
			head -c 67108864 /dev/zero | tr '\0' 'q'
			printf '"}]}}\n'
			;;
		exit) exit 3 ;;
		fail) printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32000,"message":"it broke"}}\n' "$id" ;;
		*) reply "$id" "$(text "unknown $name")" ;;
		esac
		;;
	"") ;;
	*)
		# A notification needs no answer; anything else with an id gets one.
		if [ -n "$id" ]; then
			printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32601,"message":"no %s"}}\n' "$id" "$method"
		fi
		;;
	esac
done

if [ -e "$dir/stubborn" ]; then
	while :; do sleep 1; done
fi
