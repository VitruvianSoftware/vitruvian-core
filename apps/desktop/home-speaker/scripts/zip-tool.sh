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

# The HomeSpeaker tool for the Vitruvian app, as the app installs it: a zip
# of the tool's folder with vitruvian-tool.json at the top and bin/tool, no
# folder of its own, no links. Named HomeSpeaker-<version>-tool.zip so the
# shared packaging helper (tools/desktop-package) checksums and uploads it
# with the app's own artifacts, which it finds by that prefix.
#
#   scripts/zip-tool.sh <universal homespeaker-tool binary> <version> <dist dir>
#
# Prints the zip's size and SHA-256, which a catalog entry
# (catalog/tools.json) pins.
set -euo pipefail

BINARY="${1:?Usage: zip-tool.sh <homespeaker-tool binary> <version> <dist dir>}"
VERSION="${2:?Missing version}"
DIST="${3:?Missing dist dir}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${APP_DIR}/tool/vitruvian-tool.json"

if [[ "${HOMESPEAKER_REQUIRE_UNIVERSAL:-0}" == "1" ]]; then
	archs="$(lipo -archs "${BINARY}")"
	if [[ "${archs}" != *arm64* || "${archs}" != *x86_64* ]]; then
		echo "error: expected a universal tool binary, got: ${archs}" >&2
		exit 1
	fi
fi

manifest_version="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "${MANIFEST}" | head -1)"
if [[ "${manifest_version}" != "${VERSION}" ]]; then
	echo "error: tool/vitruvian-tool.json says ${manifest_version}, the release is ${VERSION}" >&2
	exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
mkdir -p "${STAGE}/homespeaker/bin"
cp "${MANIFEST}" "${STAGE}/homespeaker/vitruvian-tool.json"
cp "${BINARY}" "${STAGE}/homespeaker/bin/tool"
chmod 755 "${STAGE}/homespeaker/bin/tool"

mkdir -p "${DIST}"
ASSET="${DIST}/HomeSpeaker-${VERSION}-tool.zip"
rm -f "${ASSET}"
(cd "${STAGE}/homespeaker" && zip -q -r -X "${ASSET}" .)

echo "==> ${ASSET}"
echo "size: $(stat -f %z "${ASSET}")"
echo "sha256: $(shasum -a 256 "${ASSET}" | cut -d' ' -f1)"
