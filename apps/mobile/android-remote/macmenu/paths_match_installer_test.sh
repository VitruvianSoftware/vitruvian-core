#!/usr/bin/env bash
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

# The menu finds the agent by the paths macagent/install.sh writes. Those are
# duplicated in Sources/RemoteMenuCore/AgentStatus.swift, so fail here when
# either side changes alone: otherwise the menu would say "Agent not
# installed" about an agent that is running fine.
set -euo pipefail
installer="$1"
swift="$2"
fail=0
check() {
	grep -qF -- "$2" "$installer" || {
		echo "install.sh no longer contains: $2" >&2
		fail=1
	}
	grep -qF -- "$3" "$swift" || {
		echo "AgentStatus.swift no longer contains: $3" >&2
		fail=1
	}
	echo "ok: $1"
}
check "label" 'LABEL="com.vitruvian.remote-agent"' '"com.vitruvian.remote-agent"'
check "binary" 'BIN_DIR="${HOME}/.local/bin"' '".local/bin/vitruvian-remote-agent"'
check "binary name" 'BIN="${BIN_DIR}/vitruvian-remote-agent"' 'vitruvian-remote-agent"'
check "log" 'LOG="${LOG_DIR}/vitruvian-remote-agent.log"' '"Library/Logs/vitruvian-remote-agent.log"'
check "log dir" 'LOG_DIR="${HOME}/Library/Logs"' 'Library/Logs/'
check "port" 'http://127.0.0.1:7411' '"http://127.0.0.1:7411"'
exit "$fail"
