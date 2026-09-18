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

VERSION="${VERSION:-1.0.0}"

echo "==> Packaging HomeSpeaker release v${VERSION}${TAG:+ (tag: ${TAG})}"

cd "${APP_DIR}"

echo "==> Building release binary with SwiftPM"
swift build -c release

echo "==> Assembling standalone HomeSpeaker.app bundle"
./scripts/bundle.sh .build/release/HomeSpeaker "${VERSION}" ./dist

ZIP_NAME="HomeSpeaker-${VERSION}-macOS.zip"
echo "==> Packaging ${ZIP_NAME}"
(cd dist && rm -f "${ZIP_NAME}" && zip -r -q "${ZIP_NAME}" HomeSpeaker.app)

if [[ "${DRY_RUN}" == "true" ]]; then
	echo "==> Dry run: verified dist/${ZIP_NAME} successfully created."
	exit 0
fi

if [[ -z "${TAG}" ]]; then
	echo "==> No TAG specified; package created at dist/${ZIP_NAME}. Skipping upload."
	exit 0
fi

REPO="${GITHUB_REPOSITORY:-VitruvianSoftware/vitruvian-core}"
echo "==> Attaching dist/${ZIP_NAME} to GitHub Release ${TAG} in ${REPO}"
gh release upload "${TAG}" "dist/${ZIP_NAME}" --repo "${REPO}" --clobber
echo "==> Upload completed successfully."
