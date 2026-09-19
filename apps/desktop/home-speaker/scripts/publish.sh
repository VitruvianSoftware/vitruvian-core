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
# The multi-arch product dir differs between Xcode and Command Line Tools
# toolchains (.build/apple vs .build/out); ask SwiftPM rather than guess.
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/HomeSpeaker"
lipo -info "${BIN}"

echo "==> Assembling standalone HomeSpeaker.app bundle"
HOMESPEAKER_REQUIRE_UNIVERSAL=1 ./scripts/bundle.sh "${BIN}" "${VERSION}" ./dist

ZIP_NAME="HomeSpeaker-${VERSION}-macOS.zip"
echo "==> Packaging ${ZIP_NAME}"
(
	cd dist
	rm -f "${ZIP_NAME}" "${ZIP_NAME}.sha256"
	# ditto keeps the bundle's extended attributes and symlinks intact, which
	# `zip -r` does not; a bundle re-signed by codesign needs that.
	ditto -c -k --keepParent HomeSpeaker.app "${ZIP_NAME}"
	shasum -a 256 "${ZIP_NAME}" >"${ZIP_NAME}.sha256"
	cat "${ZIP_NAME}.sha256"
)

if [[ "${DRY_RUN}" == "true" ]]; then
	echo "==> Dry run: verified dist/${ZIP_NAME} successfully created."
	exit 0
fi

if [[ -z "${TAG}" ]]; then
	echo "==> No TAG specified; package created at dist/${ZIP_NAME}. Skipping upload."
	exit 0
fi

REPO="${GITHUB_REPOSITORY:-VitruvianSoftware/vitruvian-core}"
echo "==> Attaching dist/${ZIP_NAME} (+ .sha256) to GitHub Release ${TAG} in ${REPO}"
gh release upload "${TAG}" "dist/${ZIP_NAME}" "dist/${ZIP_NAME}.sha256" --repo "${REPO}" --clobber
echo "==> Upload completed successfully."
