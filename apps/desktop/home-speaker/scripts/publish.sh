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

create_dmg() {
	local app_path="$1"
	local out_dmg="$2"
	local volname="HomeSpeaker"
	local work stage
	work="$(mktemp -d)"
	stage="$(mktemp -d)"
	ditto "${app_path}" "${stage}/HomeSpeaker.app"
	ln -s /Applications "${stage}/Applications"
	local rw="${work}/rw.dmg"
	hdiutil create -volname "${volname}" -srcfolder "${stage}" -fs HFS+ -format UDRW -ov "${rw}" -quiet
	rm -f "${out_dmg}"
	hdiutil convert "${rw}" -format UDZO -imagekey zlib-level=9 -o "${out_dmg}" -quiet
	rm -rf "${work}" "${stage}"
}

echo "==> Creating DMGs (universal, arm64, x86_64)"
create_dmg dist/stage-universal/HomeSpeaker.app "dist/HomeSpeaker-${VERSION}-universal.dmg"
create_dmg dist/stage-arm64/HomeSpeaker.app "dist/HomeSpeaker-${VERSION}-arm64.dmg"
create_dmg dist/stage-x86_64/HomeSpeaker.app "dist/HomeSpeaker-${VERSION}-x86_64.dmg"

echo "==> Packaging ZIPs (universal and legacy macOS)"
ditto -c -k --keepParent dist/stage-universal/HomeSpeaker.app "dist/HomeSpeaker-${VERSION}-universal.zip"
ditto -c -k --keepParent dist/stage-universal/HomeSpeaker.app "dist/HomeSpeaker-${VERSION}-macOS.zip"

echo "==> Generating SHA256 checksums"
for f in dist/HomeSpeaker-${VERSION}-*.dmg dist/HomeSpeaker-${VERSION}-*.zip; do
	shasum -a 256 "$f" > "${f}.sha256"
	cat "${f}.sha256"
done

if [[ "${DRY_RUN}" == "true" ]]; then
	echo "==> Dry run: verified all release artifacts successfully created in dist/:"
	ls -lh dist/HomeSpeaker-${VERSION}-*
	exit 0
fi

if [[ -z "${TAG}" ]]; then
	echo "==> No TAG specified; packages created in dist/. Skipping upload."
	exit 0
fi

REPO="${GITHUB_REPOSITORY:-VitruvianSoftware/vitruvian-core}"
echo "==> Attaching release artifacts to GitHub Release ${TAG} in ${REPO}"
for f in dist/HomeSpeaker-${VERSION}-*.dmg dist/HomeSpeaker-${VERSION}-*.dmg.sha256 dist/HomeSpeaker-${VERSION}-*.zip dist/HomeSpeaker-${VERSION}-*.zip.sha256; do
	echo "Uploading $(basename "$f")..."
	gh release upload "${TAG}" "$f" --repo "${REPO}" --clobber
done

if [[ -n "${HOMEBREW_TAP_TOKEN:-}" ]]; then
	TAP="VitruvianSoftware/homebrew-tap"
	TAP_DIR="$(mktemp -d)/tap"
	git clone --depth 1 "https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/${TAP}.git" "${TAP_DIR}"
	mkdir -p "${TAP_DIR}/Casks"
	UNIVERSAL_DMG="dist/HomeSpeaker-${VERSION}-universal.dmg"
	UNIVERSAL_DMG_SHA="$(shasum -a 256 "${UNIVERSAL_DMG}" | cut -d' ' -f1)"
	cat >"${TAP_DIR}/Casks/home-speaker.rb" <<EOF
cask "home-speaker" do
  version "${VERSION}"
  sha256 "${UNIVERSAL_DMG_SHA}"

  url "https://github.com/VitruvianSoftware/vitruvian-core/releases/download/home-speaker-v${VERSION}/HomeSpeaker-${VERSION}-universal.dmg"
  name "HomeSpeaker"
  desc "macOS menu bar app for speech notifications and smart speaker announcements"
  homepage "https://github.com/VitruvianSoftware/vitruvian-core/tree/main/apps/desktop/home-speaker"

  app "HomeSpeaker.app"
end
EOF
	git -C "${TAP_DIR}" add Casks/home-speaker.rb
	if git -C "${TAP_DIR}" diff --cached --quiet; then
		echo "publish: ${TAP} already has home-speaker ${VERSION}"
	else
		git -C "${TAP_DIR}" -c user.name="github-actions[bot]" \
			-c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
			commit -q -m "home-speaker ${VERSION}"
		git -C "${TAP_DIR}" push -q origin HEAD
		echo "publish: ${TAP} Casks/home-speaker.rb is now ${VERSION}"
	fi
	rm -rf "${TAP_DIR}"
fi

echo "==> Upload completed successfully."
