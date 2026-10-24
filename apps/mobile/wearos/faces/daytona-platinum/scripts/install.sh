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

# Build and install the Daytona Platinum 126506 WFF watch face onto an attached
# Wear OS watch (defaults to Pixel Watch 4 serial 58301WRBNL30SD).

set -euo pipefail

if [[ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]]; then
	PKG_DIR="${BUILD_WORKSPACE_DIRECTORY}/apps/mobile/wearos/faces/daytona-platinum"
else
	SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	PKG_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

WORK_APK="$(mktemp -t daytona-platinum).apk"
trap 'rm -f "${WORK_APK}"' EXIT

bash "${PKG_DIR}/scripts/build_wff_apk.sh" "${WORK_APK}"

WATCH_SERIAL="${ANDROID_SERIAL:-}"
if [[ -z "${WATCH_SERIAL}" ]]; then
	WATCH_SERIAL="$(adb devices | awk '/58301WRBNL30SD/ && $2 == "device" {print $1; exit}')"
fi

if [[ -z "${WATCH_SERIAL}" ]]; then
	echo "error: Pixel Watch 4 (58301WRBNL30SD) is not connected over ADB. Wake the watch screen and run: bazel run //tools/adb-connect -- --device watch" >&2
	exit 1
fi

echo "Installing onto ${WATCH_SERIAL}..."
adb -s "${WATCH_SERIAL}" install -r -i com.android.vending "${WORK_APK}"
adb -s "${WATCH_SERIAL}" shell am broadcast \
	-a com.google.android.wearable.dwf.receiver.MARKETPLACE_ADDED \
	-n com.google.android.wearable.dwf.receiver/.monitor.MarketplacePackageChangesMonitor \
	--es MARKETPLACE_PACKAGE_NAME com.watchfacestudio.daytonaplatinum >/dev/null 2>&1 || true

echo "Installed com.watchfacestudio.daytonaplatinum on ${WATCH_SERIAL}."
