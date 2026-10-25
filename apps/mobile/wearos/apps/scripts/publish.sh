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

# Builds the multi-ABI release APKs for all 4 Vitruvian Wear OS apps:
#   1. VitruvianPulse-<version>.apk      (//apps/mobile/wearos/apps/vitruvian-pulse:app)
#   2. VitruvianWearRemote-<version>.apk (//apps/mobile/wearos/apps/remote:app)
#   3. VitruvianHomeControl-<version>.apk (//apps/mobile/wearos/apps/home-control:app)
#   4. VitruvianNexusWrist-<version>.apk (//apps/mobile/wearos/apps/nexus-wrist:app)
# Computes SHA-256 sidecars, and — when TAG is set — attaches all 8 files to the GitHub Release.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SUITE_DIR}/../../../.." && pwd)"

DRY_RUN=false
for arg in "$@"; do
	if [[ "$arg" == "--dry-run" ]]; then
		DRY_RUN=true
	fi
done

TAG="${TAG:-}"
VERSION="${VERSION:-}"

if [[ -z "${VERSION}" && -n "${TAG}" ]]; then
	VERSION="${TAG#wearos-apps-v}"
	VERSION="${VERSION#v}"
fi

if [[ -z "${VERSION}" && -f "${SUITE_DIR}/.release-please-manifest.json" ]]; then
	VERSION="$(grep -o '"apps/mobile/wearos/apps": *"[^"]*"' "${SUITE_DIR}/.release-please-manifest.json" | cut -d'"' -f4 || true)"
fi
VERSION="${VERSION:-0.1.0}"

echo "==> Packaging Vitruvian Wear OS Apps Suite release v${VERSION}${TAG:+ (tag: ${TAG})}"

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

if [[ -z "${ANDROID_HOME:-}" ]]; then
	if [[ "${DRY_RUN}" == "true" ]]; then
		echo "==> Dry run: ANDROID_HOME is unset; skipping local build check."
		exit 0
	else
		echo "Error: ANDROID_HOME is unset. A local Android SDK is required to build the Wear OS release APKs." >&2
		exit 1
	fi
fi

cd "${REPO_ROOT}"

echo "==> Building all 4 Wear OS release APKs with Bazel"
bazel build \
	--android_platforms=@rules_android//:armeabi-v7a,@rules_android//:arm64-v8a,@rules_android//:x86_64 \
	//apps/mobile/wearos/apps/vitruvian-pulse:app \
	//apps/mobile/wearos/apps/remote:app \
	//apps/mobile/wearos/apps/home-control:app \
	//apps/mobile/wearos/apps/nexus-wrist:app

BIN_ROOT="$(bazel info bazel-bin)"
rm -rf "${SUITE_DIR}/dist"
mkdir -p "${SUITE_DIR}/dist"

declare -a APK_SPECS=(
	"vitruvian-pulse:VitruvianPulse-${VERSION}.apk"
	"remote:VitruvianWearRemote-${VERSION}.apk"
	"home-control:VitruvianHomeControl-${VERSION}.apk"
	"nexus-wrist:VitruvianNexusWrist-${VERSION}.apk"
)

UPLOAD_FILES=()
for spec in "${APK_SPECS[@]}"; do
	pkg="${spec%%:*}"
	apk_name="${spec#*:}"
	src_apk="${BIN_ROOT}/apps/mobile/wearos/apps/${pkg}/app.apk"
	if [[ ! -f "${src_apk}" ]]; then
		echo "Error: Expected APK output at ${src_apk} not found" >&2
		exit 1
	fi
	cp -L "${src_apk}" "${SUITE_DIR}/dist/${apk_name}"
	if command -v sha256sum >/dev/null 2>&1; then
		(cd "${SUITE_DIR}/dist" && sha256sum "${apk_name}" >"${apk_name}.sha256")
	else
		(cd "${SUITE_DIR}/dist" && shasum -a 256 "${apk_name}" >"${apk_name}.sha256")
	fi
	cat "${SUITE_DIR}/dist/${apk_name}.sha256"
	UPLOAD_FILES+=("${SUITE_DIR}/dist/${apk_name}" "${SUITE_DIR}/dist/${apk_name}.sha256")
done

if [[ "${DRY_RUN}" == "true" ]]; then
	echo "==> Dry run: verified all 4 Wear OS APKs and SHA256 checksums in dist/:"
	ls -lh "${SUITE_DIR}/dist"
	exit 0
fi

if [[ -z "${TAG}" ]]; then
	echo "==> No TAG specified; packages created in dist/. Skipping upload."
	exit 0
fi

REPO="${GITHUB_REPOSITORY:-VitruvianSoftware/vitruvian-core}"
echo "==> Attaching Wear OS release artifacts to GitHub Release ${TAG} in ${REPO}"
gh release upload "${TAG}" \
	"${UPLOAD_FILES[@]}" \
	--repo "${REPO}" \
	--clobber

echo "==> Upload completed successfully."
