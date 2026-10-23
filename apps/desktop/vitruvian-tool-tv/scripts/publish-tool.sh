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

# Builds the Vitruvian TV extension (dev.vitruvian.tv) as a self-contained
# Protocol 2 folder, zips it as VitruvianTV-<version>-tool.zip with a SHA-256
# sidecar, and, when TAG is set, attaches both to that GitHub Release.
#
#   TAG=vitruvian-tool-tv-vX.Y.Z bash apps/desktop/vitruvian-tool-tv/scripts/publish-tool.sh
#   bash apps/desktop/vitruvian-tool-tv/scripts/publish-tool.sh --dry-run

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT="$(cd "${TOOL_DIR}/../../.." && pwd)"
PKG="apps/desktop/vitruvian-tool-tv"

DRY_RUN=false
for arg in "$@"; do
	case "${arg}" in
	--dry-run) DRY_RUN=true ;;
	*)
		echo "error: unknown argument ${arg} (only --dry-run)" >&2
		exit 2
		;;
	esac
done

TAG="${TAG:-}"
VERSION="${VERSION:-}"
if [[ -z "${VERSION}" && -n "${TAG}" ]]; then
	VERSION="${TAG#vitruvian-tool-tv-v}"
fi
if [[ -z "${VERSION}" ]]; then
	VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "${TOOL_DIR}/vitruvian-tool.json" | head -1)"
fi

manifest_version="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "${TOOL_DIR}/vitruvian-tool.json" | head -1)"
if [[ "${manifest_version}" != "${VERSION}" ]]; then
	echo "error: vitruvian-tool.json says ${manifest_version}, the release is ${VERSION}" >&2
	exit 1
fi

echo "==> Packaging Vitruvian TV extension v${VERSION}${TAG:+ (tag: ${TAG})}"

flags=()
if [[ -n "${BUILDBUDDY_API_KEY:-}" ]]; then
	flags+=(--config=remotecache-ci "--remote_header=x-buildbuddy-api-key=${BUILDBUDDY_API_KEY}")
fi

WORK="${RUNNER_TEMP:-$(mktemp -d)}/vitruvian-tv-dist"
rm -rf "${WORK}"
mkdir -p "${WORK}/stage" "${WORK}/dist"

cd "${ROOT}"
bazel build ${flags[@]+"${flags[@]}"} "//${PKG}:tool-folder"
BUILT_DIR="${ROOT}/bazel-bin/${PKG}/built/vitruvian-tv"
if [[ ! -f "${BUILT_DIR}/vitruvian-tool.json" ]]; then
	echo "error: bazel left no built/vitruvian-tv/vitruvian-tool.json" >&2
	exit 1
fi

cp -R "${BUILT_DIR}/." "${WORK}/stage/"
chmod -R u+w "${WORK}/stage"
chmod 755 "${WORK}/stage/bin/tool.py"

ASSET="VitruvianTV-${VERSION}-tool.zip"
(cd "${WORK}/stage" && zip -q -r -X "${WORK}/dist/${ASSET}" .)

if command -v sha256sum >/dev/null 2>&1; then
	(cd "${WORK}/dist" && sha256sum "${ASSET}" >"${ASSET}.sha256")
else
	(cd "${WORK}/dist" && shasum -a 256 "${ASSET}" >"${ASSET}.sha256")
fi

cat "${WORK}/dist/${ASSET}.sha256"
if stat -c %s "${WORK}/dist/${ASSET}" >/dev/null 2>&1; then
	SIZE="$(stat -c %s "${WORK}/dist/${ASSET}")"
else
	SIZE="$(stat -f %z "${WORK}/dist/${ASSET}")"
fi
echo "==> ${WORK}/dist/${ASSET} (size: ${SIZE})"

if [[ "${DRY_RUN}" == "true" ]]; then
	echo "==> Dry run: the extension's zip is in ${WORK}/dist; nothing uploaded."
	exit 0
fi
if [[ -z "${TAG}" ]]; then
	echo "==> No TAG: the extension's zip is in ${WORK}/dist; nothing uploaded."
	exit 0
fi

REPO="${GITHUB_REPOSITORY:-VitruvianSoftware/vitruvian-core}"
echo "==> Attaching ${ASSET} to GitHub Release ${TAG} in ${REPO}"
gh release upload "${TAG}" "${WORK}/dist/${ASSET}" "${WORK}/dist/${ASSET}.sha256" \
	--repo "${REPO}" --clobber
echo "==> Upload completed."
