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

# Builds a universal (Apple Silicon + Intel) HomeSpeaker.app, zips it with a
# SHA-256 sidecar, and — when TAG is set — attaches both to the GitHub Release.

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
	VERSION="${TAG#home-speaker-v}"
	VERSION="${VERSION#v}"
fi

# Fall back to the version release-please stamped into the source.
if [[ -z "${VERSION}" ]]; then
	VERSION="$(sed -n 's/.*current = "\([^"]*\)".*/\1/p' "${APP_DIR}/Sources/HomeSpeakerCore/Version.swift")"
fi

echo "==> Packaging HomeSpeaker release v${VERSION}${TAG:+ (tag: ${TAG})}"

cd "${APP_DIR}"

echo "==> Building universal release binary with SwiftPM"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/HomeSpeaker"
lipo -info "${BIN}"

BIN_DIR="$(dirname "${BIN}")"
BIN_ARM64="${BIN_DIR}/HomeSpeaker-arm64"
BIN_X86_64="${BIN_DIR}/HomeSpeaker-x86_64"
lipo "${BIN}" -thin arm64 -output "${BIN_ARM64}"
lipo "${BIN}" -thin x86_64 -output "${BIN_X86_64}"

echo "==> Assembling standalone HomeSpeaker.app bundles (universal, arm64, x86_64)"
rm -rf dist
mkdir -p dist/stage-universal dist/stage-arm64 dist/stage-x86_64

HOMESPEAKER_REQUIRE_UNIVERSAL=1 ./scripts/bundle.sh "${BIN}" "${VERSION}" ./dist/stage-universal
./scripts/bundle.sh "${BIN_ARM64}" "${VERSION}" ./dist/stage-arm64
./scripts/bundle.sh "${BIN_X86_64}" "${VERSION}" ./dist/stage-x86_64

# Keep dist/HomeSpeaker.app pointing to universal bundle for local workflows
ditto dist/stage-universal/HomeSpeaker.app dist/HomeSpeaker.app

ROOT="$(cd "${APP_DIR}/../.." && pwd)"
PACKAGE_HELPER="${ROOT}/tools/desktop-package/package-desktop.sh"

echo "==> Invoking shared tools/desktop-package helper for packaging and release distribution"
EXTRA_ARGS=()
if [[ "${DRY_RUN}" == "true" ]]; then
	EXTRA_ARGS+=(--dry-run)
fi
if [[ -n "${TAG}" ]]; then
	EXTRA_ARGS+=(--tag "${TAG}")
fi

bash "${PACKAGE_HELPER}" \
	--app-path "${APP_DIR}/dist/HomeSpeaker.app" \
	--app-name "HomeSpeaker" \
	--version "${VERSION}" \
	--cask-name "home-speaker" \
	--cask-desc "macOS menu bar app for speech notifications and smart speaker announcements" \
	--cask-homepage "https://github.com/VitruvianSoftware/vitruvian-core/tree/main/apps/desktop/home-speaker" \
	--dist-dir "${APP_DIR}/dist" \
	--sync-downloads \
	"${EXTRA_ARGS[@]}"

echo "==> HomeSpeaker release packaging completed successfully."
