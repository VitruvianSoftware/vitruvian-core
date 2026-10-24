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

# Builds and installs all 4 Vitruvian Wear OS apps onto a connected Pixel Watch 4 over ADB.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SUITE_DIR}/../../../.." && pwd)"

if [[ -n "${BUILD_WORKING_DIRECTORY:-}" && -f "${BUILD_WORKING_DIRECTORY}/MODULE.bazel" ]]; then
	REPO_ROOT="${BUILD_WORKING_DIRECTORY}"
fi

if [[ -z "${ANDROID_HOME:-}" ]]; then
	for cand in \
		"/usr/local/lib/android/sdk" \
		"/opt/homebrew/share/android-commandlinetools" \
		"${HOME}/Library/Android/sdk"; do
		if [[ -d "${cand}/platforms" ]]; then
			export ANDROID_HOME="${cand}"
			break
		fi
	done
fi

cd "${REPO_ROOT}"

echo "==> Building all 4 Vitruvian Wear OS APKs..."
bazel build \
	--android_platforms=@rules_android//:arm64-v8a \
	//apps/mobile/wearos/apps/vitruvian-pulse:app \
	//apps/mobile/wearos/apps/remote:app \
	//apps/mobile/wearos/apps/home-control:app \
	//apps/mobile/wearos/apps/nexus-wrist:app

BIN_ROOT="$(bazel info bazel-bin)"
ADB_ARGS=()
if [[ -n "${ANDROID_SERIAL:-}" ]]; then
	ADB_ARGS=(-s "${ANDROID_SERIAL}")
fi

for pkg in vitruvian-pulse remote home-control nexus-wrist; do
	apk="${BIN_ROOT}/apps/mobile/wearos/apps/${pkg}/app.apk"
	echo "==> Installing ${pkg} (${apk})..."
	adb "${ADB_ARGS[@]}" install -r "${apk}"
done

echo "==> All 4 Vitruvian Wear OS apps installed on watch."
