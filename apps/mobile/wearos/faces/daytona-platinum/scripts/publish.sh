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

# Builds the signed Declarative Watch Face Format (WFF) release APK for
# Daytona Platinum 126506 (apps/mobile/wearos/faces/daytona-platinum), computes
# a SHA-256 sidecar, and — when TAG is set — attaches both to the GitHub Release.

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
	VERSION="${TAG#daytona-platinum-v}"
	VERSION="${VERSION#v}"
fi

if [[ -z "${VERSION}" && -f "${APP_DIR}/.release-please-manifest.json" ]]; then
	VERSION="$(grep -o '"apps/mobile/wearos/faces/daytona-platinum": *"[^"]*"' "${APP_DIR}/.release-please-manifest.json" | cut -d'"' -f4)"
fi
VERSION="${VERSION:-0.1.0}"

echo "==> Packaging Daytona Platinum Watch Face release v${VERSION}${TAG:+ (tag: ${TAG})}"

if [[ -z "${ANDROID_HOME:-}" ]]; then
	if [[ -d "/usr/local/lib/android/sdk" ]]; then
		export ANDROID_HOME="/usr/local/lib/android/sdk"
	elif [[ -d "/opt/homebrew/share/android-commandlinetools" ]]; then
		export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
	fi
fi

rm -rf "${APP_DIR}/dist"
mkdir -p "${APP_DIR}/dist"

APK_NAME="DaytonaPlatinum-${VERSION}.apk"
bash "${SCRIPT_DIR}/build_wff_apk.sh" "${APP_DIR}/dist/${APK_NAME}"

echo "==> Generating SHA256 checksum"
if command -v sha256sum >/dev/null 2>&1; then
	(cd "${APP_DIR}/dist" && sha256sum "${APK_NAME}" >"${APK_NAME}.sha256")
else
	(cd "${APP_DIR}/dist" && shasum -a 256 "${APK_NAME}" >"${APK_NAME}.sha256")
fi
cat "${APP_DIR}/dist/${APK_NAME}.sha256"

if [[ "${DRY_RUN}" == "true" ]]; then
	echo "==> Dry run: verified release artifact created in dist/:"
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
