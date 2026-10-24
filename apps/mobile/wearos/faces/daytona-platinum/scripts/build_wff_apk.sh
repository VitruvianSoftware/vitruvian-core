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

# Package a pure Declarative Watch Face Format (WFF) APK with no classes.dex.
#
# Wear OS 5+ rejects WFF packages (`android:hasCode="false"`) that contain a
# classes.dex entry, so this script compiles and links only resources and the
# manifest via aapt2, aligns with zipalign, and signs with apksigner.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_APK="${1:-${PKG_DIR}/daytona-platinum.apk}"

SDK_ROOT="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
BUILD_TOOLS_DIR="$(ls -d "${SDK_ROOT}/build-tools/"* 2>/dev/null | sort -V | tail -n 1)"
PLATFORM_JAR="$(ls "${SDK_ROOT}/platforms/"android-*/android.jar 2>/dev/null | sort -V | tail -n 1)"

if [[ -z "${BUILD_TOOLS_DIR}" || -z "${PLATFORM_JAR}" ]]; then
	echo "error: Android SDK build-tools and platforms/android-*/android.jar are required under ANDROID_HOME (${SDK_ROOT})" >&2
	exit 1
fi

if [[ -z "${JAVA_HOME:-}" && -d "/opt/homebrew/opt/openjdk" ]]; then
	export JAVA_HOME="/opt/homebrew/opt/openjdk"
fi

AAPT2="${BUILD_TOOLS_DIR}/aapt2"
ZIPALIGN="${BUILD_TOOLS_DIR}/zipalign"
APKSIGNER="${BUILD_TOOLS_DIR}/apksigner"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

"${AAPT2}" compile --dir "${PKG_DIR}/src/main/res" -o "${WORK_DIR}/compiled_res.zip"
"${AAPT2}" link \
	-o "${WORK_DIR}/unaligned.apk" \
	-I "${PLATFORM_JAR}" \
	--manifest "${PKG_DIR}/src/main/AndroidManifest.xml" \
	--auto-add-overlay \
	"${WORK_DIR}/compiled_res.zip"

"${ZIPALIGN}" -f -p 4 "${WORK_DIR}/unaligned.apk" "${WORK_DIR}/aligned.apk"

KEYSTORE="${HOME}/.android/debug.keystore"
if [[ ! -f "${KEYSTORE}" ]]; then
	mkdir -p "${HOME}/.android"
	keytool -genkeypair \
		-keystore "${KEYSTORE}" \
		-storepass android \
		-alias androiddebugkey \
		-keypass android \
		-keyalg RSA \
		-keysize 2048 \
		-validity 10000 \
		-dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi

mkdir -p "$(dirname "${OUT_APK}")"
"${APKSIGNER}" sign \
	--ks "${KEYSTORE}" \
	--ks-pass pass:android \
	--key-pass pass:android \
	--ks-key-alias androiddebugkey \
	--out "${OUT_APK}" \
	"${WORK_DIR}/aligned.apk"

echo "Built signed WFF APK: ${OUT_APK}"
