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

# Builds the Vitruvian Remote extension for the Vitruvian app as one program
# for Apple silicon and Intel, zips it as VitruvianRemote-<version>-tool.zip
# with a SHA-256 sidecar (scripts/zip-tool.sh), and, when TAG is set, attaches
# both to that GitHub Release, beside the APK scripts/publish.sh attaches.
#
#   TAG=android-remote-vX.Y.Z bash apps/mobile/android-remote/macmenu/scripts/publish-tool.sh
#   bash apps/mobile/android-remote/macmenu/scripts/publish-tool.sh --dry-run
#
# Needs a Mac with Xcode. Builds :tool-folder twice with Bazel, once per
# architecture, and joins each program's two halves with lipo: neither
# swift_binary nor go_binary makes a universal program by itself. Nothing it
# builds is run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACMENU_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT="$(cd "${MACMENU_DIR}/../../../.." && pwd)"
PKG="apps/mobile/android-remote/macmenu"

DRY_RUN=false
for arg in "$@"; do
	case "${arg}" in
	--dry-run) DRY_RUN=true ;;
	*)
		# A misspelt --dry-run must not upload.
		echo "error: unknown argument ${arg} (only --dry-run)" >&2
		exit 2
		;;
	esac
done

TAG="${TAG:-}"
VERSION="${VERSION:-}"
if [[ -z "${VERSION}" && -n "${TAG}" ]]; then
	VERSION="${TAG#android-remote-v}"
fi
# Absent both, the version release-please wrote into the manifest.
if [[ -z "${VERSION}" ]]; then
	VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "${MACMENU_DIR}/tool/vitruvian-tool.json" | head -1)"
fi

echo "==> Packaging the Vitruvian Remote extension v${VERSION}${TAG:+ (tag: ${TAG})}"

# The oldest macOS the extension supports: the menu bar app's, which is the
# Vitruvian app's (14.0). Without it Bazel builds for the SDK's own macOS
# (Xcode 27's: 27.0), and the extension would install on macOS 14 to 26 and
# then never start; no Intel Mac runs macOS 27 at all. zip-tool.sh checks
# every architecture of both programs against it.
MIN_MACOS="$(plutil -extract LSMinimumSystemVersion raw -o - "${MACMENU_DIR}/Resources/Info.plist")"
if [[ ! "${MIN_MACOS}" =~ ^[0-9]+\.[0-9]+$ ]]; then
	echo "error: Resources/Info.plist's LSMinimumSystemVersion is '${MIN_MACOS}'" >&2
	exit 1
fi

flags=(--config=macos-app -c opt "--macos_minimum_os=${MIN_MACOS}")
if [[ -n "${BUILDBUDDY_API_KEY:-}" ]]; then
	# Cache-only: reuse what the macOS lanes already built. Absent (a laptop,
	# a fork), build locally.
	flags+=(--config=remotecache-ci "--remote_header=x-buildbuddy-api-key=${BUILDBUDDY_API_KEY}")
fi

WORK="${RUNNER_TEMP:-$(mktemp -d)}/remote-tool-dist"
rm -rf "${WORK}"
mkdir -p "${WORK}/arm64" "${WORK}/x86_64" "${WORK}/universal" "${WORK}/dist"

cd "${ROOT}"
for arch in arm64 x86_64; do
	echo "==> Building the extension for ${arch}"
	arch_flags=("${flags[@]}" "--platforms=@apple_support//platforms:macos_${arch}")
	bazel build "${arch_flags[@]}" "//${PKG}:tool-folder"
	# Both architectures build to the same output path, so each is copied out
	# before the next build replaces it.
	outputs="$(bazel cquery "${arch_flags[@]}" --output=files "//${PKG}:tool-folder")"
	for program in tool vitruvian-remote-agent; do
		# No match must reach the clear error below, not end the script here.
		built="$({ grep "/built/remote/bin/${program}\$" <<<"${outputs}" || true; } | head -1)"
		if [[ -z "${built}" || ! -f "${built}" ]]; then
			echo "error: bazel left no bin/${program} for ${arch}" >&2
			exit 1
		fi
		cp "${built}" "${WORK}/${arch}/${program}"
		got="$(lipo -archs "${WORK}/${arch}/${program}")"
		if [[ "${got}" != "${arch}" ]]; then
			echo "error: the ${arch} build of bin/${program} is '${got}'" >&2
			exit 1
		fi
	done
done

for program in tool vitruvian-remote-agent; do
	lipo -create "${WORK}/arm64/${program}" "${WORK}/x86_64/${program}" \
		-output "${WORK}/universal/${program}"
	lipo -info "${WORK}/universal/${program}"
	# The linker signs only the Apple silicon half (ad hoc), so `codesign -v`
	# calls the joined program unsigned. Sign both halves ad hoc; no identity
	# is involved.
	codesign --force --sign - "${WORK}/universal/${program}"
	codesign --verify --strict "${WORK}/universal/${program}"
done

REMOTE_TOOL_REQUIRE_UNIVERSAL=1 REMOTE_TOOL_MAX_MINOS="${MIN_MACOS}" bash "${SCRIPT_DIR}/zip-tool.sh" \
	"${WORK}/universal/tool" "${WORK}/universal/vitruvian-remote-agent" \
	"${VERSION}" "${WORK}/dist"

ASSET="VitruvianRemote-${VERSION}-tool.zip"
(cd "${WORK}/dist" && shasum -a 256 "${ASSET}" >"${ASSET}.sha256")
cat "${WORK}/dist/${ASSET}.sha256"
for file in "${ASSET}" "${ASSET}.sha256"; do
	if [[ ! -s "${WORK}/dist/${file}" ]]; then
		echo "error: packaging left no ${file}" >&2
		exit 1
	fi
done

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
