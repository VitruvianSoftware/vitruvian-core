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

# The HomeSpeaker tool for the Vitruvian app, beside the app: one zip of its
# folder, named so the packaging helper below uploads it with the rest.
echo "==> Zipping the HomeSpeaker tool for the Vitruvian app"
TOOL_BIN="$(dirname "${BIN}")/homespeaker-tool"
lipo -info "${TOOL_BIN}"
HOMESPEAKER_REQUIRE_UNIVERSAL=1 ./scripts/zip-tool.sh "${TOOL_BIN}" "${VERSION}" ./dist

HOMESPEAKER_REQUIRE_UNIVERSAL=1 ./scripts/bundle.sh "${BIN}" "${VERSION}" ./dist/stage-universal
./scripts/bundle.sh "${BIN_ARM64}" "${VERSION}" ./dist/stage-arm64
./scripts/bundle.sh "${BIN_X86_64}" "${VERSION}" ./dist/stage-x86_64

# Keep dist/HomeSpeaker.app pointing to universal bundle for local workflows
ditto dist/stage-universal/HomeSpeaker.app dist/HomeSpeaker.app

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "${APP_DIR}/../../.." && pwd))"
PACKAGE_HELPER="${ROOT}/tools/desktop-package/package-desktop.sh"
TOOL_ZIP="HomeSpeaker-${VERSION}-tool.zip"

echo "==> Invoking shared tools/desktop-package helper for packaging and release distribution"
EXTRA_ARGS=()
if [[ "${DRY_RUN}" == "true" ]]; then
	EXTRA_ARGS+=(--dry-run)
fi
if [[ -n "${TAG}" ]]; then
	EXTRA_ARGS+=(--tag "${TAG}")
fi

if [[ -f "${PACKAGE_HELPER}" ]]; then
	PACKAGE_CMD=(bash "${PACKAGE_HELPER}")
else
	PKG_TMP="$(mktemp -d)"
	trap 'rm -rf "${PKG_TMP}"' EXIT
	rustc --edition 2021 --crate-type lib --crate-name package_desktop "${ROOT}/tools/desktop-package/src/lib.rs" -o "${PKG_TMP}/libpackage_desktop.rlib"
	rustc --edition 2021 "${ROOT}/tools/desktop-package/src/main.rs" -L "${PKG_TMP}" --extern package_desktop="${PKG_TMP}/libpackage_desktop.rlib" -o "${PKG_TMP}/package-desktop"
	PACKAGE_CMD=("${PKG_TMP}/package-desktop")
fi

"${PACKAGE_CMD[@]}" \
	--app-path "${APP_DIR}/dist/HomeSpeaker.app" \
	--app-name "HomeSpeaker" \
	--version "${VERSION}" \
	--cask-name "home-speaker" \
	--cask-desc "macOS menu bar app for speech notifications and smart speaker announcements" \
	--cask-homepage "https://github.com/VitruvianSoftware/vitruvian-core/tree/main/apps/desktop/home-speaker" \
	--dist-dir "${APP_DIR}/dist" \
	--sync-downloads \
	--require-asset "${TOOL_ZIP}" \
	${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
# EXTRA_ARGS is empty on a plain local run. macOS's bash 3.2 ends the script on
# a bare "${EXTRA_ARGS[@]}" under `set -u`, hence the guarded form above.

# The helper's exit status is not taken on trust: 1.12.0 and 1.13.0 were
# released with no files because it stopped half way and still exited 0. What
# HomeSpeaker ships must be in dist, each with its checksum, or this fails.
# (On a real release the helper has also read the same list back from GitHub,
# and the workflow's last step does so once more.)
missing=0
for artifact in \
	"HomeSpeaker-${VERSION}-universal.dmg" \
	"HomeSpeaker-${VERSION}-arm64.dmg" \
	"HomeSpeaker-${VERSION}-x86_64.dmg" \
	"HomeSpeaker-${VERSION}-universal.zip" \
	"${TOOL_ZIP}"; do
	for file in "${artifact}" "${artifact}.sha256"; do
		if [[ ! -s "${APP_DIR}/dist/${file}" ]]; then
			echo "error: packaging left no ${file} in dist" >&2
			missing=1
		fi
	done
done
if [[ "${missing}" -ne 0 ]]; then
	echo "error: HomeSpeaker ${VERSION} was NOT packaged; see the helper's output above" >&2
	exit 1
fi

echo "==> HomeSpeaker release packaging completed successfully."
