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

# The Vitruvian Remote extension for the Vitruvian app, as the app installs it
# from the catalog: a zip of the extension's folder with vitruvian-tool.json at
# the top, bin/tool, and bin/vitruvian-remote-agent (the agent the extension
# runs), no folder of its own, no links. The same three files as the
# :tool-folder target. Named VitruvianRemote-<version>-tool.zip, beside the
# release's VitruvianRemote-<version>.apk.
#
#   scripts/zip-tool.sh <remote-tool binary> <vitruvian-remote-agent binary> <version> <dist dir>
#
# With REMOTE_TOOL_REQUIRE_UNIVERSAL=1 (the release sets it) both programs must
# hold Apple silicon and Intel code. The version must be the one
# tool/vitruvian-tool.json says.
#
# Prints the zip's size and SHA-256, which a catalog entry
# (catalog/tools.json) pins.
set -euo pipefail

TOOL="${1:?Usage: zip-tool.sh <remote-tool binary> <agent binary> <version> <dist dir>}"
AGENT="${2:?Missing the vitruvian-remote-agent binary}"
VERSION="${3:?Missing version}"
DIST="${4:?Missing dist dir}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACMENU_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${MACMENU_DIR}/tool/vitruvian-tool.json"

if [[ "${REMOTE_TOOL_REQUIRE_UNIVERSAL:-0}" == "1" ]]; then
	for binary in "${TOOL}" "${AGENT}"; do
		archs="$(lipo -archs "${binary}")"
		if [[ "${archs}" != *arm64* || "${archs}" != *x86_64* ]]; then
			echo "error: expected a universal binary, ${binary} is: ${archs}" >&2
			exit 1
		fi
	done
fi

manifest_version="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "${MANIFEST}" | head -1)"
if [[ "${manifest_version}" != "${VERSION}" ]]; then
	echo "error: tool/vitruvian-tool.json says ${manifest_version}, the release is ${VERSION}" >&2
	exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
mkdir -p "${STAGE}/remote/bin"
cp "${MANIFEST}" "${STAGE}/remote/vitruvian-tool.json"
# cp follows links, so what lands in the folder is a plain file even when
# Bazel's output is one.
cp "${TOOL}" "${STAGE}/remote/bin/tool"
cp "${AGENT}" "${STAGE}/remote/bin/vitruvian-remote-agent"
chmod 644 "${STAGE}/remote/vitruvian-tool.json"
chmod 755 "${STAGE}/remote/bin/tool" "${STAGE}/remote/bin/vitruvian-remote-agent"

# The zip is made from inside the staging folder, so the dist folder is made
# whole first: `./dist` would otherwise name a folder in the staging one.
mkdir -p "${DIST}"
DIST="$(cd "${DIST}" && pwd)"
ASSET="${DIST}/VitruvianRemote-${VERSION}-tool.zip"
rm -f "${ASSET}"
(cd "${STAGE}/remote" && zip -q -r -X "${ASSET}" .)

echo "==> ${ASSET}"
echo "size: $(stat -f %z "${ASSET}")"
echo "sha256: $(shasum -a 256 "${ASSET}" | cut -d' ' -f1)"
