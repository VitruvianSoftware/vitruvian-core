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

# Build and publish the gravastar-mouse command to a GitHub Release, and (for a
# release) its Homebrew formula.
#
# ONE script, TWO triggers (delivery-orchestrator spec §4.1): the generated
# .github/workflows/delivery-gravastar-mouse.yaml runs it for the
# `gravastar-mouse` unit, and the break-glass path is
# `bazel run //packages/peripherals:publish` on a Mac. The rung selects the grade:
#
#   GRADE=beta        (push to main)  rolling prerelease `gravastar-mouse-beta-latest`;
#                     the asset is overwritten and the tag is moved to HEAD.
#   GRADE=production  (release event) attach the asset to the release-please
#                     release named by RELEASE_TAG (gravastar-mouse-vX.Y.Z), then
#                     update Formula/gravastar-mouse.rb in
#                     VitruvianSoftware/homebrew-tap when HOMEBREW_TAP_TOKEN is set.
#
# The binary is universal (arm64 + x86_64) and signed ad hoc by rules_apple.
#
# Break-glass for production: check out the release tag, then
#   GRADE=production RELEASE_TAG=gravastar-mouse-vX.Y.Z bazel run --config=macos-app //packages/peripherals:publish
set -euo pipefail

cd "${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ROOT="$(pwd)"
PKG="packages/peripherals"
REPO="VitruvianSoftware/vitruvian-core"
TAP="VitruvianSoftware/homebrew-tap"

GRADE="${GRADE:-beta}"
SHA="${GITHUB_SHA:-$(git rev-parse HEAD)}"
MANIFEST_VER="$(jq -r '."packages/peripherals"' "${PKG}/.release-please-manifest.json")"
TAG_PREFIX="gravastar-mouse-v"

case "${GRADE}" in
beta)
	TAG="${TAG:-gravastar-mouse-beta-latest}"
	VERSION="${MANIFEST_VER}-beta.${SHA:0:7}"
	ASSET="gravastar-mouse-beta-macos.tar.gz"
	;;
production)
	# A dispatch of the production rung carries no release event, and
	# re-uploading a release's asset from a different commit would silently
	# replace what was released. Require the tag explicitly; never guess it.
	TAG="${RELEASE_TAG:-}"
	if [[ -z "${TAG}" ]]; then
		echo "publish: GRADE=production needs RELEASE_TAG=${TAG_PREFIX}X.Y.Z (the release-please tag); refusing to guess" >&2
		exit 2
	fi
	if [[ "${TAG}" != "${TAG_PREFIX}"* ]]; then
		echo "publish: RELEASE_TAG=${TAG} is not a ${TAG_PREFIX}* release; another component's release reached this rung" >&2
		exit 2
	fi
	VERSION="${TAG#"${TAG_PREFIX}"}"
	if [[ "${VERSION}" != "${MANIFEST_VER}" ]]; then
		echo "publish: ${TAG} is version ${VERSION}, but this checkout is ${MANIFEST_VER}; check out the release tag first" >&2
		exit 2
	fi
	ASSET="gravastar-mouse-${VERSION}-macos.tar.gz"
	;;
*)
	echo "publish: unknown GRADE=${GRADE} (beta|production)" >&2
	exit 2
	;;
esac

echo "=== gravastar-mouse publish: grade=${GRADE} version=${VERSION} tag=${TAG} commit=${SHA} ==="

flags=(--config=macos-app "--macos_cpus=arm64,x86_64")
if [[ -n "${BUILDBUDDY_API_KEY:-}" ]]; then
	flags+=(--config=remotecache-ci "--remote_header=x-buildbuddy-api-key=${BUILDBUDDY_API_KEY}")
fi
bazel build "${flags[@]}" "//${PKG}:gravastar-mouse"
BINARY="$(bazel cquery "${flags[@]}" --output=files "//${PKG}:gravastar-mouse" 2>/dev/null |
	grep '/gravastar-mouse$' | head -1)"
if [[ -z "${BINARY}" || ! -x "${BINARY}" ]]; then
	echo "publish: bazel produced no gravastar-mouse binary for //${PKG}:gravastar-mouse" >&2
	exit 1
fi

# What the release promises: both architectures, and the version it is named for.
archs="$(lipo -archs "${BINARY}")"
for arch in arm64 x86_64; do
	if [[ " ${archs} " != *" ${arch} "* ]]; then
		echo "publish: ${BINARY} is '${archs}', missing ${arch}" >&2
		exit 1
	fi
done
reported="$("${BINARY}" --version)"
if [[ "${reported}" != "${MANIFEST_VER}" ]]; then
	echo "publish: the binary reports ${reported}, but the manifest is ${MANIFEST_VER} (CLI.version out of step?)" >&2
	exit 1
fi

WORK="${RUNNER_TEMP:-$(mktemp -d)}/gravastar-mouse-dist"
rm -rf "${WORK}"
mkdir -p "${WORK}/stage"
cp "${BINARY}" "${WORK}/stage/gravastar-mouse"
chmod 755 "${WORK}/stage/gravastar-mouse"
cp "${PKG}/LICENSE" "${PKG}/README.md" "${WORK}/stage/"
tar -czf "${WORK}/${ASSET}" -C "${WORK}/stage" gravastar-mouse LICENSE README.md
DIGEST="$(shasum -a 256 "${WORK}/${ASSET}" | cut -d' ' -f1)"
echo "${DIGEST}  ${ASSET}" >"${WORK}/${ASSET}.sha256"
echo "${ASSET}: sha256 ${DIGEST}"

cd "${ROOT}"

if [[ "${GRADE}" == "beta" ]]; then
	gh release view "${TAG}" >/dev/null 2>&1 ||
		gh release create "${TAG}" --prerelease \
			--target "${SHA}" \
			--title "gravastar-mouse (Beta Rolling Release)" \
			--notes "Rolling pre-release built automatically from commits landing on main."
fi

gh release upload "${TAG}" "${WORK}/${ASSET}" "${WORK}/${ASSET}.sha256" --clobber

if [[ "${GRADE}" == "beta" ]]; then
	# Move the rolling tag to the commit whose asset now sits on the release.
	gh api -X PATCH "repos/{owner}/{repo}/git/refs/tags/${TAG}" \
		-f sha="${SHA}" -F force=true >/dev/null
	gh release edit "${TAG}" \
		--notes "Latest beta build: ${VERSION}
Commit: ${SHA}

${ASSET}: the universal (arm64 + x86_64) gravastar-mouse command, with its LICENSE and README.
sha256: ${DIGEST}"
	echo "=== gravastar-mouse publish complete: ${TAG} (${VERSION}, beta) ==="
	exit 0
fi

if [[ -z "${HOMEBREW_TAP_TOKEN:-}" ]]; then
	echo "publish: HOMEBREW_TAP_TOKEN is not set; skipping the ${TAP} formula update"
	echo "=== gravastar-mouse publish complete: ${TAG} (${VERSION}, production) ==="
	exit 0
fi

TAP_DIR="${WORK}/tap"
git clone --depth 1 "https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/${TAP}.git" "${TAP_DIR}"
mkdir -p "${TAP_DIR}/Formula"
cat >"${TAP_DIR}/Formula/gravastar-mouse.rb" <<FORMULA
# Generated by packages/peripherals/publish.sh in ${REPO}; do not edit here.
class GravastarMouse < Formula
  desc "Status light and MCP server for the RGB LED of a GravaStar mouse"
  homepage "https://github.com/${REPO}/tree/main/packages/peripherals"
  url "https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"
  version "${VERSION}"
  sha256 "${DIGEST}"
  license "MIT"

  depends_on macos: :sonoma

  def install
    bin.install "gravastar-mouse"
  end

  test do
    assert_equal version.to_s, shell_output("#{bin}/gravastar-mouse --version").strip
  end
end
FORMULA
git -C "${TAP_DIR}" add Formula/gravastar-mouse.rb
if git -C "${TAP_DIR}" diff --cached --quiet; then
	echo "publish: ${TAP} already has gravastar-mouse ${VERSION}"
else
	git -C "${TAP_DIR}" -c user.name="github-actions[bot]" \
		-c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
		commit -q -m "gravastar-mouse ${VERSION}"
	git -C "${TAP_DIR}" push -q origin HEAD
	echo "publish: ${TAP} Formula/gravastar-mouse.rb is now ${VERSION}"
fi

echo "=== gravastar-mouse publish complete: ${TAG} (${VERSION}, production) ==="
