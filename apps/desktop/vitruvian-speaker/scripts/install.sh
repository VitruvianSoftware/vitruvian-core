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

# Installs the latest Vitruvian Speaker release into /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/VitruvianSoftware/vitruvian-core/main/apps/desktop/vitruvian-speaker/scripts/install.sh | bash
#
# Vitruvian Speaker is not notarized (no paid Apple Developer ID), so a browser
# download is blocked by Gatekeeper. This script downloads it directly,
# verifies the published SHA-256, and clears the quarantine flag so it opens.
# Set VITRUVIAN_SPEAKER_VERSION=x.y.z to pin a version.

set -euo pipefail

REPO="VitruvianSoftware/vitruvian-core"
DEST="${VITRUVIAN_SPEAKER_DEST:-/Applications}"

if [[ "$(uname -s)" != "Darwin" ]]; then
	echo "Vitruvian Speaker is a macOS app." >&2
	exit 1
fi
if [[ "$(sw_vers -productVersion | cut -d. -f1)" -lt 14 ]]; then
	echo "Vitruvian Speaker needs macOS 14 (Sonoma) or newer." >&2
	exit 1
fi

if [[ -n "${VITRUVIAN_SPEAKER_VERSION:-}" ]]; then
	TAG="vitruvian-speaker-v${VITRUVIAN_SPEAKER_VERSION#v}"
else
	echo "==> Finding the latest Vitruvian Speaker release"
	TAG="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases?per_page=50" |
		sed -n 's/.*"tag_name": *"\(vitruvian-speaker-v[^"]*\)".*/\1/p' | head -1)"
	if [[ -z "${TAG}" ]]; then
		echo "Could not find a vitruvian-speaker release on ${REPO}." >&2
		exit 1
	fi
fi
VERSION="${TAG#vitruvian-speaker-v}"
ZIP="VitruvianSpeaker-${VERSION}-macOS.zip"
BASE="https://github.com/${REPO}/releases/download/${TAG}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

echo "==> Downloading ${ZIP}"
curl -fsSL -o "${WORK}/${ZIP}" "${BASE}/${ZIP}"
if curl -fsSL -o "${WORK}/${ZIP}.sha256" "${BASE}/${ZIP}.sha256" 2>/dev/null; then
	echo "==> Verifying checksum"
	(cd "${WORK}" && shasum -a 256 -c "${ZIP}.sha256")
else
	echo "==> No checksum published for this release; skipping verification"
fi

echo "==> Installing to ${DEST}/Vitruvian Speaker.app"
ditto -x -k "${WORK}/${ZIP}" "${WORK}/unpacked"
if pgrep -xq VitruvianSpeaker; then
	osascript -e 'tell application "Vitruvian Speaker" to quit' >/dev/null 2>&1 || true
	sleep 1
fi
rm -rf "${DEST}/Vitruvian Speaker.app"
ditto "${WORK}/unpacked/Vitruvian Speaker.app" "${DEST}/Vitruvian Speaker.app"
# The zip was fetched by curl, not a browser, so it is normally not quarantined;
# clear it anyway in case the user downloaded it by hand first. Use the system
# xattr by full path: the `xattr` PyPI package shadows it on many machines and
# its build has no -r flag.
/usr/bin/xattr -dr com.apple.quarantine "${DEST}/Vitruvian Speaker.app" 2>/dev/null ||
	find "${DEST}/Vitruvian Speaker.app" -print0 | xargs -0 /usr/bin/xattr -c 2>/dev/null || true

echo "==> Launching Vitruvian Speaker ${VERSION}"
open "${DEST}/Vitruvian Speaker.app"
echo "Done. Look for the speaker icon in your menu bar."
