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

# Build, stamp and publish the ESP32-S3 firmware bundle to a GitHub Release.
#
# ONE script, TWO triggers (delivery-orchestrator spec §4.1): the generated
# .github/workflows/delivery.yaml runs it for the `esp32-s3` unit, and the
# break-glass path is `bazel run //iot/esp32-s3:publish`. The rung selects the
# grade:
#
#   GRADE=beta        (push to main)  rolling prerelease `esp32-s3-beta-latest`;
#                     assets are overwritten and the tag is moved to HEAD.
#   GRADE=production  (release event) attach the assets to the release-please
#                     release named by RELEASE_TAG (esp32-s3-vX.Y.Z).
#
# Stamping happens HERE and not in the Bazel genrule: a genrule's action sees
# neither the workflow's env nor .git, so GRADE/VERSION/commit can only be
# known outside it. The genrule produces the three raw images; this script
# wraps them with build_info.json + flash.sh into the distributable zip.
#
# Break-glass for production: check out the release tag, then
#   GRADE=production RELEASE_TAG=esp32-s3-vX.Y.Z bazel run //iot/esp32-s3:publish
set -euo pipefail

cd "${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ROOT="$(pwd)"
PKG="iot/esp32-s3"

GRADE="${GRADE:-beta}"
SHA="${GITHUB_SHA:-$(git rev-parse HEAD)}"
SHORT_SHA="${SHA:0:7}"
MANIFEST_VER="$(jq -r '."iot/esp32-s3"' "${PKG}/.release-please-manifest.json")"
TAG_PREFIX="esp32-s3-v"

case "${GRADE}" in
beta)
	TAG="${TAG:-esp32-s3-beta-latest}"
	VERSION="${MANIFEST_VER}-beta.${SHORT_SHA}"
	;;
production)
	# A dispatch of the production rung carries no release event, and
	# re-uploading a release's assets from a different commit would silently
	# replace what was released. Require the tag explicitly; never guess it.
	TAG="${RELEASE_TAG:-}"
	if [[ -z "${TAG}" ]]; then
		echo "publish: GRADE=production needs RELEASE_TAG=${TAG_PREFIX}X.Y.Z (the release-please tag); refusing to guess" >&2
		exit 2
	fi
	if [[ "${TAG}" != "${TAG_PREFIX}"* ]]; then
		echo "publish: RELEASE_TAG=${TAG} is not an ${TAG_PREFIX}* release; another component's release reached this rung" >&2
		exit 2
	fi
	VERSION="${TAG#"${TAG_PREFIX}"}"
	;;
*)
	echo "publish: unknown GRADE=${GRADE} (beta|production)" >&2
	exit 2
	;;
esac

echo "=== esp32-s3 publish: grade=${GRADE} version=${VERSION} tag=${TAG} commit=${SHA} ==="

bazel build "//${PKG}:firmware"

WORK="${RUNNER_TEMP:-$(mktemp -d)}/esp32-s3-dist"
rm -rf "${WORK}"
mkdir -p "${WORK}"
for img in firmware bootloader partitions; do
	cp "bazel-bin/${PKG}/${img}.bin" "${WORK}/${img}.bin"
	chmod +w "${WORK}/${img}.bin"
done
# The flasher is the checked-in one, not a copy: it already handles binaries
# sitting beside it (the bundle layout) as well as a PlatformIO build tree.
cp "${PKG}/flash.sh" "${WORK}/flash.sh"
chmod +x "${WORK}/flash.sh"

BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat >"${WORK}/build_info.json" <<EOF
{
  "version": "${VERSION}",
  "grade": "${GRADE}",
  "commit": "${SHA}",
  "builtAt": "${BUILT_AT}",
  "board": "Waveshare ESP32-S3-Touch-LCD-1.69",
  "mcu": "ESP32-S3",
  "flash_size": "16MB",
  "framework": "arduino",
  "lvgl_version": "8.4.0"
}
EOF

ZIP="${WORK}/esp32-s3-mac-controller.zip"
(cd "${WORK}" && zip -q "${ZIP}" firmware.bin bootloader.bin partitions.bin build_info.json flash.sh)

cd "${ROOT}"

if [[ "${GRADE}" == "beta" ]]; then
	gh release view "${TAG}" >/dev/null 2>&1 ||
		gh release create "${TAG}" --prerelease \
			--target "${SHA}" \
			--title "ESP32-S3 Firmware (Beta Rolling Release)" \
			--notes "Rolling pre-release built automatically from commits landing on main."
fi

gh release upload "${TAG}" \
	"${WORK}/firmware.bin" \
	"${WORK}/bootloader.bin" \
	"${WORK}/partitions.bin" \
	"${WORK}/build_info.json" \
	"${ZIP}" \
	--clobber

if [[ "${GRADE}" == "beta" ]]; then
	# Move the rolling tag to the commit whose assets now sit on the release, so
	# the release page's "compare"/source links agree with build_info.json.
	# A tag update through the API is a contents: write operation on a ref no
	# ruleset protects (only the merge-queue branch ruleset exists); a failure
	# here is a real failure, not something to paper over.
	gh api -X PATCH "repos/{owner}/{repo}/git/refs/tags/${TAG}" \
		-f sha="${SHA}" -F force=true >/dev/null

	gh release edit "${TAG}" \
		--notes "Latest Beta Firmware Build: ${VERSION}
Commit: ${SHA}
Built: ${BUILT_AT}

Artifacts Included:
* firmware.bin: Application binary (Flash at 0x10000)
* bootloader.bin: ESP32-S3 second-stage bootloader (Flash at 0x0000)
* partitions.bin: 16MB partition table (Flash at 0x8000)
* build_info.json: version / grade / commit stamp
* esp32-s3-mac-controller.zip: Full flashable archive with flash.sh."
fi

echo "=== esp32-s3 publish complete: ${TAG} (${VERSION}, ${GRADE}) ==="
