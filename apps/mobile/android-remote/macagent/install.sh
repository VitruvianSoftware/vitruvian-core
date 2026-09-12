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
#
# install.sh -- install vitruvian-remote-agent as a login item for THIS user.
#
# No sudo. The agent reads the machine with unprivileged tools only, so it is
# installed as a user LaunchAgent (~/Library/LaunchAgents), not a system
# LaunchDaemon. Compare tools/ops/macos-power-agent, which needs root for
# powermetrics and is installed system-wide for that reason.
#
# Run via bazel so the binary is the one the repo built:
#   bazel run //mobile/android/remote/macagent:install
#
# Idempotent: re-running replaces the binary and restarts the agent.
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
	echo "install.sh: this agent only runs on macOS" >&2
	exit 1
fi
if [ "$(id -u)" -eq 0 ]; then
	echo "install.sh: do not run as root -- this is a per-user login item" >&2
	exit 1
fi

# Under `bazel run`, the binary and plist are RUNFILES, which live in a tree
# beside the script rather than next to it: $RUNFILES_DIR when bazel sets
# it, else $0.runfiles. The package path inside that tree is fixed.
RUNFILES="${RUNFILES_DIR:-$0.runfiles}"
SRC_DIR="${RUNFILES}/_main/apps/mobile/android-remote/macagent"
if [ ! -d "$SRC_DIR" ]; then
	# Run directly from a checkout instead: fall back to the script's own dir
	# and expect a prebuilt binary beside it.
	SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
BIN_SRC="${SRC_DIR}/macagent_/macagent"
[ -x "$BIN_SRC" ] || BIN_SRC="${SRC_DIR}/macagent"
if [ ! -x "$BIN_SRC" ] || [ ! -f "${SRC_DIR}/com.vitruvian.remote-agent.plist" ]; then
	echo "install.sh: built agent or plist not found under ${SRC_DIR} (run via: bazel run //apps/mobile/android-remote/macagent:install)" >&2
	exit 1
fi

# Everything after the script name is handed to the agent as flags and baked
# into the plist, e.g.
#   bazel run //mobile/android/remote/macagent:install -- \
#     --kubeconfig ~/.kube/cluster.yaml --kube-context default \
#     --prometheus-url https://grafana.example/api/datasources/proxy/uid/X \
#     --prometheus-token-file ~/.config/vitruvian-remote-agent/prometheus-token
# A leading ~ in a flag VALUE is expanded here: launchd runs no shell.
ARGS_XML=""
for arg in "$@"; do
	case "$arg" in
	"~" | "~/"*) arg="${HOME}${arg#\~}" ;;
	esac
	# XML-escape the four characters that matter inside <string>.
	esc=$(printf '%s' "$arg" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g')
	ARGS_XML="${ARGS_XML}		<string>${esc}</string>\n"
done

LABEL="com.vitruvian.remote-agent"
BIN_DIR="${HOME}/.local/bin"
BIN="${BIN_DIR}/vitruvian-remote-agent"
LOG_DIR="${HOME}/Library/Logs"
LOG="${LOG_DIR}/vitruvian-remote-agent.log"
PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST="${PLIST_DIR}/${LABEL}.plist"

install -d -m 0755 "$BIN_DIR" "$LOG_DIR" "$PLIST_DIR"
install -m 0755 "$BIN_SRC" "$BIN"

# Sign with a stable identity when one exists. macOS ties Screen Recording
# (and every other TCC grant) to the binary's designated requirement. An
# ad-hoc signed Go binary's requirement is its cdhash, which changes on every
# build -- so every reinstall silently revoked the grant while the pane still
# showed it ON. With a self-signed "Vitruvian Remote Agent" certificate in
# the login keychain the requirement becomes identifier + certificate, and
# a grant made once outlives rebuilds. Without one, fall through ad-hoc and
# say so, because the symptom is a 503 with a misleading next step.
SIGN_ID="Vitruvian Remote Agent"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"${SIGN_ID}\""; then
	codesign -f -s "$SIGN_ID" -i dev.vitruvian.remote-agent "$BIN" 2>/dev/null
	SIGNED="signed as \"${SIGN_ID}\" (TCC grants survive reinstalls)"
else
	SIGNED="ad-hoc signed: re-grant Screen Recording after EVERY reinstall, or create the \"${SIGN_ID}\" identity (see README)"
fi
sed -e "s|__BIN__|${BIN}|g" -e "s|__LOG__|${LOG}|g" "${SRC_DIR}/${LABEL}.plist" |
	awk -v args="$ARGS_XML" '{ if ($0 ~ /^__ARGS__$/) { printf "%s", args } else { print } }' >"$PLIST"
plutil -lint "$PLIST" >/dev/null
chmod 0644 "$PLIST"

UID_NUM="$(id -u)"
launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true
# bootout returns before the job is gone; a bootstrap in that gap fails with
# "5: Input/output error" and the agent stays down. Seen one reinstall in three.
for _ in $(seq 1 50); do
	launchctl print "gui/${UID_NUM}/${LABEL}" >/dev/null 2>&1 || break
	sleep 0.2
done
launchctl bootstrap "gui/${UID_NUM}" "$PLIST"
launchctl enable "gui/${UID_NUM}/${LABEL}"
launchctl kickstart -k "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true

# Prove it rather than assume it: the agent answers within a second of
# starting, and a silent install that did not is the failure this line
# exists to catch.
for _ in 1 2 3 4 5 6 7 8 9 10; do
	if curl -fsS --max-time 1 "http://127.0.0.1:7411/healthz" >/dev/null 2>&1; then
		echo "vitruvian-remote-agent installed and answering on http://127.0.0.1:7411"
		echo "  signing: ${SIGNED}"
		echo "  binary: ${BIN}"
		echo "  args:   $(plutil -extract ProgramArguments json -o - "$PLIST" 2>/dev/null | tr -d '\n')"
		echo "  plist:  ${PLIST}"
		echo "  log:    ${LOG}"
		echo "  try:    curl -s http://127.0.0.1:7411/v1/metrics | jq ."
		# The phone bridge's MCP token. The PATH, never the value: the point
		# of the file is that only a process on this Mac can read it, and
		# echoing it here would put it in a terminal scrollback and in
		# whatever captured this install's output.
		echo "  mcp:    ${HOME}/.config/vitruvian-remote-agent/mcp-token (0600) -- the phone bridge's token"
		echo "          claude mcp add --transport http phone http://127.0.0.1:7411/mcp/phone \\"
		echo "            --header \"Authorization: Bearer \$(cat ~/.config/vitruvian-remote-agent/mcp-token)\""
		echo "  remove: launchctl bootout gui/${UID_NUM}/${LABEL}; rm ${PLIST} ${BIN}"
		exit 0
	fi
	sleep 0.5
done
echo "install.sh: agent did not answer on :7411 within 5s -- see ${LOG}" >&2
exit 1
