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

# install.sh -- put the Vitruvian Remote menu bar app in /Applications and open it.
#
#   bazel run --config=macos-app //apps/mobile/android-remote/macmenu:install
#
# The app only shows and steers the agent; install the agent itself with
# //apps/mobile/android-remote/macagent:install. Idempotent: re-running
# replaces the app and relaunches it.
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
	echo "install.sh: Vitruvian Remote is a macOS app" >&2
	exit 1
fi

DEST="${VITRUVIAN_REMOTE_DEST:-/Applications}"
RUNFILES="${RUNFILES_DIR:-$0.runfiles}"
ZIP="${RUNFILES}/_main/apps/mobile/android-remote/macmenu/VitruvianRemote.zip"
if [ ! -f "$ZIP" ]; then
	echo "install.sh: built app not found at ${ZIP} (run via: bazel run --config=macos-app //apps/mobile/android-remote/macmenu:install)" >&2
	exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
ditto -x -k "$ZIP" "$WORK"

if pgrep -xq VitruvianRemote; then
	osascript -e 'tell application id "com.vitruviansoftware.remote" to quit' >/dev/null 2>&1 || pkill -x VitruvianRemote || true
	for _ in $(seq 1 20); do
		pgrep -xq VitruvianRemote || break
		sleep 0.2
	done
fi

rm -rf "${DEST}/VitruvianRemote.app"
ditto "${WORK}/VitruvianRemote.app" "${DEST}/VitruvianRemote.app"
open "${DEST}/VitruvianRemote.app"

# Prove it launched rather than assume it.
for _ in $(seq 1 25); do
	if pgrep -xq VitruvianRemote; then
		echo "Vitruvian Remote installed at ${DEST}/VitruvianRemote.app and running."
		echo "Look for the V icon in the menu bar. Turn on Open at Login from its menu."
		exit 0
	fi
	sleep 0.2
done
echo "install.sh: the app did not start; try: open ${DEST}/VitruvianRemote.app" >&2
exit 1
