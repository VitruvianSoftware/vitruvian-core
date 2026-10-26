#!/bin/bash
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

# Install (or refresh) the vitruvian macos-power-agent LaunchDaemon on this Mac.
# Idempotent. Run as root:
#   sudo ./install.sh [instance-name]
# instance-name defaults to the lowercased short hostname (matches tailnet names).
# Override the push target with PUSHGATEWAY_URL=... in the environment.
set -euo pipefail

if [ "$("${ID_BIN:-id}" -u)" -ne 0 ]; then
	echo "install.sh: must run as root (use sudo)" >&2
	exit 1
fi

INSTANCE="${1:-$(hostname -s | tr '[:upper:]' '[:lower:]')}"
PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-https://pushgateway.lab.ipv1337.dev}"
SRC_DIR="${SRC_DIR:-$(cd "$(dirname "$0")" && pwd)}"
LABEL="com.vitruvian.power-agent"
DEST_ROOT="${DEST_ROOT:-}"
PLIST="${DEST_ROOT}/Library/LaunchDaemons/${LABEL}.plist"

"${INSTALL_BIN:-install}" -d -m 0755 "${DEST_ROOT}/usr/local/bin" "${DEST_ROOT}/usr/local/etc" "${DEST_ROOT}/var/log"
"${INSTALL_BIN:-install}" -m 0755 "${AGENT_SRC:-$SRC_DIR/power-agent.sh}" "${DEST_ROOT}/usr/local/bin/vitruvian-power-agent"

umask 022
cat >"${DEST_ROOT}/usr/local/etc/vitruvian-power-agent.conf" <<EOF
# Written by macos-power-agent install.sh — edit and reload the daemon to change.
INSTANCE="${INSTANCE}"
PUSHGATEWAY_URL="${PUSHGATEWAY_URL}"
JOB="mac_power"
EOF

"${INSTALL_BIN:-install}" -m 0644 "$SRC_DIR/${LABEL}.plist" "$PLIST"
"${CHOWN_BIN:-chown}" root:wheel "$PLIST" "${DEST_ROOT}/usr/local/bin/vitruvian-power-agent"

# Reload: bootout any existing instance, then bootstrap the (possibly updated) one.
"${LAUNCHCTL_BIN:-launchctl}" bootout "system/${LABEL}" 2>/dev/null || true
"${LAUNCHCTL_BIN:-launchctl}" bootstrap system "$PLIST"
"${LAUNCHCTL_BIN:-launchctl}" enable "system/${LABEL}"
"${LAUNCHCTL_BIN:-launchctl}" kickstart "system/${LABEL}" 2>/dev/null || true

echo "macos-power-agent installed: instance=${INSTANCE} target=${PUSHGATEWAY_URL}"
echo "logs: /var/log/vitruvian-power-agent.log   (first push within ~30s)"
