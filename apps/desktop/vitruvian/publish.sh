#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

# Build, package and publish the Vitruvian DMG to a GitHub Release.
#
# ONE script, TWO triggers (delivery-orchestrator spec §4.1): the generated
# .github/workflows/delivery-vitruvian.yaml runs it for the `vitruvian` unit, and the
# break-glass path is `bazel run //apps/desktop/vitruvian:publish`. The rung
# selects the grade:
#
#   GRADE=beta        (push to main)  rolling prerelease `vitruvian-beta-latest`;
#                     its Vitruvian-beta.dmg is overwritten and the tag moved
#                     to HEAD.
#   GRADE=production  (release event) attach Vitruvian-X.Y.Z.dmg to the
#                     release-please release named by RELEASE_TAG
#                     (vitruvian-vX.Y.Z).
#
# macOS only: it builds the app with --config=macos-app and packages it with
# Tools/package-release.sh, which signs with the Developer ID identity when one
# is in the keychain (ad-hoc otherwise) and notarizes when NOTARY_* are set.
#
# Break-glass for production, on a Mac: check out the release tag, then
#   GRADE=production RELEASE_TAG=vitruvian-vX.Y.Z bazel run //apps/desktop/vitruvian:publish
set -euo pipefail

cd "${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ROOT="$(pwd)"
PKG="apps/desktop/vitruvian"

GRADE="${GRADE:-beta}"
SHA="${GITHUB_SHA:-$(git rev-parse HEAD)}"
TAG_PREFIX="vitruvian-v"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "${PKG}/Resources/Info.plist")"

case "${GRADE}" in
beta)
	TAG="${TAG:-vitruvian-beta-latest}"
	VERSION="${APP_VERSION}-beta.${SHA:0:7}"
	ASSET="Vitruvian-beta.dmg"
	;;
production)
	# A dispatch of the production rung carries no release event. Running it
	# from the release tag itself names the tag; anything else must say which
	# release it means, because re-uploading a release's DMG from a different
	# commit would silently replace what was released.
	TAG="${RELEASE_TAG:-}"
	if [[ -z "${TAG}" && "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
		TAG="${GITHUB_REF_NAME:-}"
	fi
	if [[ -z "${TAG}" ]]; then
		echo "publish: GRADE=production needs RELEASE_TAG=${TAG_PREFIX}X.Y.Z (the release-please tag); refusing to guess" >&2
		exit 2
	fi
	if [[ "${TAG}" != "${TAG_PREFIX}"* ]]; then
		echo "publish: RELEASE_TAG=${TAG} is not a ${TAG_PREFIX}* release; another component's release reached this rung" >&2
		exit 2
	fi
	VERSION="${TAG#"${TAG_PREFIX}"}"
	if [[ "${VERSION}" != "${APP_VERSION}" ]]; then
		echo "publish: ${TAG} is version ${VERSION}, but this checkout builds ${APP_VERSION}; check out the release tag first" >&2
		exit 2
	fi
	ASSET="Vitruvian-${VERSION}.dmg"
	;;
*)
	echo "publish: unknown GRADE=${GRADE} (beta|production)" >&2
	exit 2
	;;
esac

echo "=== vitruvian publish: grade=${GRADE} version=${VERSION} tag=${TAG} commit=${SHA} ==="

flags=(--config=macos-app "--macos_cpus=arm64,x86_64")
if [[ -n "${BUILDBUDDY_API_KEY:-}" ]]; then
	# Cache-only (see --config=remotecache-ci): reuse the build the macOS
	# pipeline unit already cached. Absent (a laptop, a fork), build locally.
	flags+=(--config=remotecache-ci "--remote_header=x-buildbuddy-api-key=${BUILDBUDDY_API_KEY}")
fi
bazel build "${flags[@]}" "//${PKG}:Vitruvian"
ARCHIVE="$(bazel cquery "${flags[@]}" --output=files "//${PKG}:Vitruvian" 2>/dev/null | grep '\.zip$' | head -1)"
if [[ -z "${ARCHIVE}" || ! -f "${ARCHIVE}" ]]; then
	echo "publish: bazel produced no Vitruvian.zip for //${PKG}:Vitruvian" >&2
	exit 1
fi

rm -rf "${PKG}/dist"
"${PKG}/Tools/package-release.sh" "${ROOT}/${ARCHIVE}"
if [[ ! -f "${PKG}/dist/Vitruvian-${APP_VERSION}-universal.dmg" ]]; then
	echo "publish: package-release.sh did not produce Vitruvian-${APP_VERSION}-universal.dmg" >&2
	exit 1
fi

WORK="${RUNNER_TEMP:-$(mktemp -d)}/vitruvian-dist"
rm -rf "${WORK}"
mkdir -p "${WORK}"

if [[ "${GRADE}" == "beta" ]]; then
	cp "${PKG}/dist/Vitruvian-${APP_VERSION}-universal.dmg" "${WORK}/Vitruvian-beta-universal.dmg"
	cp "${PKG}/dist/Vitruvian-${APP_VERSION}-arm64.dmg" "${WORK}/Vitruvian-beta-arm64.dmg"
	cp "${PKG}/dist/Vitruvian-${APP_VERSION}-x86_64.dmg" "${WORK}/Vitruvian-beta-x86_64.dmg"
	cp "${PKG}/dist/Vitruvian-${APP_VERSION}-universal.zip" "${WORK}/Vitruvian-beta-universal.zip"
	cp "${PKG}/dist/Vitruvian-${APP_VERSION}.dmg" "${WORK}/Vitruvian-beta.dmg"
else
	cp "${PKG}/dist/Vitruvian-${APP_VERSION}-universal.dmg" "${WORK}/Vitruvian-${VERSION}-universal.dmg"
	cp "${PKG}/dist/Vitruvian-${APP_VERSION}-arm64.dmg" "${WORK}/Vitruvian-${VERSION}-arm64.dmg"
	cp "${PKG}/dist/Vitruvian-${APP_VERSION}-x86_64.dmg" "${WORK}/Vitruvian-${VERSION}-x86_64.dmg"
	cp "${PKG}/dist/Vitruvian-${APP_VERSION}-universal.zip" "${WORK}/Vitruvian-${VERSION}-universal.zip"
	cp "${PKG}/dist/Vitruvian-${APP_VERSION}.dmg" "${WORK}/Vitruvian-${VERSION}.dmg"
fi

for f in "${WORK}"/*; do
	if [[ -f "$f" ]]; then
		shasum -a 256 "$f"
	fi
done

if [[ "${GRADE}" == "beta" ]]; then
	gh release view "${TAG}" >/dev/null 2>&1 ||
		gh release create "${TAG}" --prerelease \
			--target "${SHA}" \
			--title "Vitruvian (Beta Rolling Release)" \
			--notes "Rolling pre-release built automatically from commits landing on main."
fi

for f in "${WORK}"/*; do
	if [[ -f "$f" ]]; then
		echo "Uploading $(basename "$f")..."
		gh release upload "${TAG}" "$f" --clobber
	fi
done

if [[ "${GRADE}" == "beta" ]]; then
	# Move the rolling tag to the commit whose DMG now sits on the release, so
	# the release page's "compare"/source links agree with the notes.
	gh api -X PATCH "repos/{owner}/{repo}/git/refs/tags/${TAG}" \
		-f sha="${SHA}" -F force=true >/dev/null

	gh release edit "${TAG}" \
		--notes "Latest beta build: ${VERSION}
Commit: ${SHA}
Built: $(date -u +%Y-%m-%dT%H:%M:%SZ)

Vitruvian is built from main and is not a release. It is signed ad-hoc unless a Developer ID is configured, so macOS asks you to approve it on first launch (see the README's Install section)."
fi

if [[ "${GRADE}" == "production" && -n "${HOMEBREW_TAP_TOKEN:-}" ]]; then
	TAP="VitruvianSoftware/homebrew-tap"
	TAP_DIR="${WORK}/tap"
	git clone --depth 1 "https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/${TAP}.git" "${TAP_DIR}"
	mkdir -p "${TAP_DIR}/Casks"
	UNIVERSAL_DMG_SHA="$(shasum -a 256 "${WORK}/Vitruvian-${VERSION}-universal.dmg" | cut -d' ' -f1)"
	cat >"${TAP_DIR}/Casks/vitruvian.rb" <<EOF
cask "vitruvian" do
  version "${VERSION}"
  sha256 "${UNIVERSAL_DMG_SHA}"

  url "https://github.com/VitruvianSoftware/vitruvian-core/releases/download/vitruvian-v${VERSION}/Vitruvian-${VERSION}-universal.dmg"
  name "Vitruvian"
  desc "Desktop control hub for Vitruvian and AI coding sessions"
  homepage "https://github.com/VitruvianSoftware/vitruvian-core/tree/main/apps/desktop/vitruvian"

  app "Vitruvian.app"
end
EOF
	git -C "${TAP_DIR}" add Casks/vitruvian.rb
	if git -C "${TAP_DIR}" diff --cached --quiet; then
		echo "publish: ${TAP} already has vitruvian ${VERSION}"
	else
		git -C "${TAP_DIR}" -c user.name="github-actions[bot]" \
			-c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
			commit -q -m "vitruvian ${VERSION}"
		git -C "${TAP_DIR}" push -q origin HEAD
		echo "publish: ${TAP} Casks/vitruvian.rb is now ${VERSION}"
	fi
fi

echo "=== vitruvian publish complete: ${TAG} (${VERSION}, ${GRADE}) ==="
