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

# Builds the multi-ABI release APK for Vitruvian Remote (apps/mobile/android-remote:app),
# computes SHA-256 sidecars, and — when TAG is set — attaches both to the GitHub Release.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

DRY_RUN=false
for arg in "$@"; do
	if [[ "$arg" == "--dry-run" ]]; then
		DRY_RUN=true
	fi
done

TAG="${TAG:-}"
VERSION="${VERSION:-}"

if [[ -z "${VERSION}" && -n "${TAG}" ]]; then
	VERSION="${TAG#android-remote-v}"
	VERSION="${VERSION#v}"
fi

# Fall back to the version declared in the manifest or BUILD file
if [[ -z "${VERSION}" ]]; then
	if [[ -f "${APP_DIR}/.release-please-manifest.json" ]]; then
		VERSION="$(grep -o '"apps/mobile/android-remote": *"[^"]*"' "${APP_DIR}/.release-please-manifest.json" | cut -d'"' -f4)"
	elif [[ -f "${APP_DIR}/BUILD" ]]; then
		VERSION="$(grep -o '"versionName": *"[^"]*"' "${APP_DIR}/BUILD" | cut -d'"' -f4)"
	fi
fi
VERSION="${VERSION:-0.1.0}"

echo "==> Packaging Vitruvian Remote release v${VERSION}${TAG:+ (tag: ${TAG})}"

# If running on GitHub Actions or standard Linux with default Android SDK path:
if [[ -z "${ANDROID_HOME:-}" && -d "/usr/local/lib/android/sdk" ]]; then
	export ANDROID_HOME="/usr/local/lib/android/sdk"
fi

if [[ -z "${ANDROID_HOME:-}" ]]; then
	if [[ "${DRY_RUN}" == "true" ]]; then
		echo "==> Dry run: ANDROID_HOME is unset; skipping local build check."
		exit 0
	else
		echo "Error: ANDROID_HOME is unset. A local Android SDK is required to build the release APK." >&2
		exit 1
	fi
fi

cd "${APP_DIR}"

echo "==> Building Android release APK with Bazel"
bazel build \
	--android_platforms=@rules_android//:arm64-v8a,@rules_android//:x86_64 \
	//apps/mobile/android-remote:app

BIN="$(bazel info bazel-bin)/apps/mobile/android-remote/app.apk"
if [[ ! -f "${BIN}" ]]; then
	echo "Error: Expected APK output at ${BIN} not found" >&2
	exit 1
fi

rm -rf "${APP_DIR}/dist"
mkdir -p "${APP_DIR}/dist"

APK_NAME="VitruvianRemote-${VERSION}.apk"
cp -L "${BIN}" "${APP_DIR}/dist/${APK_NAME}"

echo "==> Generating SHA256 checksum"
if command -v sha256sum >/dev/null 2>&1; then
	(cd "${APP_DIR}/dist" && sha256sum "${APK_NAME}" > "${APK_NAME}.sha256")
else
	(cd "${APP_DIR}/dist" && shasum -a 256 "${APK_NAME}" > "${APK_NAME}.sha256")
fi
cat "${APP_DIR}/dist/${APK_NAME}.sha256"

if [[ "${DRY_RUN}" == "true" ]]; then
	echo "==> Dry run: verified release artifact successfully created in dist/:"
	ls -lh "${APP_DIR}/dist/${APK_NAME}" "${APP_DIR}/dist/${APK_NAME}.sha256"
	exit 0
fi

if [[ -z "${TAG}" ]]; then
	echo "==> No TAG specified; packages created in dist/. Skipping upload."
	exit 0
fi

REPO="${GITHUB_REPOSITORY:-VitruvianSoftware/vitruvian-core}"
echo "==> Attaching release artifacts to GitHub Release ${TAG} in ${REPO}"
gh release upload "${TAG}" \
	"${APP_DIR}/dist/${APK_NAME}" \
	"${APP_DIR}/dist/${APK_NAME}.sha256" \
	--repo "${REPO}" \
	--clobber

echo "==> Upload completed successfully."
