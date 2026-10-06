#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

# Turns the Bazel-built app into the release DMG, dist/Vitruvian-<version>.dmg:
#   bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian
#   apps/desktop/vitruvian/Tools/package-release.sh "$PWD/<path to Vitruvian.zip>"
#
# It unpacks the bundle and signs the fan helper, the Now Playing adapter and
# the bundle the way build.sh does: with the Developer ID identity when one is
# installed (Tools/ci-setup-signing.sh imports it on CI), ad-hoc otherwise. It
# notarizes the app and the DMG when the notary credentials are set
# (Tools/notarize.sh skips quietly when they are not), and packages the DMG with
# Tools/make-dmg.sh.
set -euo pipefail

ARCHIVE="${1:-}"
if [[ -z "$ARCHIVE" || ! -f "$ARCHIVE" ]]; then
    echo "usage: package-release.sh <path to the Bazel-built Vitruvian.zip>" >&2
    exit 1
fi
ARCHIVE="${ARCHIVE:A}"
cd "$(dirname "$0")/.."

APP_BUNDLE_ID="com.vitruviansoftware.vitruvian"
FAN_HELPER_ID="$APP_BUNDLE_ID.fan-control"
NOW_PLAYING_ADAPTER_ID="$APP_BUNDLE_ID.now-playing"
ENTITLEMENTS="Resources/Vitruvian.entitlements"
APP="build/stage/Vitruvian.app"
HELPER="$APP/Contents/Library/LaunchServices/$FAN_HELPER_ID"
ADAPTER="$APP/Contents/Frameworks/libVitruvianNowPlaying.dylib"

echo "▸ Unpacking $ARCHIVE…"
rm -rf build/stage
mkdir -p build/stage
ditto -x -k "$ARCHIVE" build/stage
for part in "$APP" "$HELPER" "$ADAPTER"; do
    if [[ ! -e "$part" ]]; then
        echo "✗ $part is missing from the archive" >&2
        exit 1
    fi
done
# Bazel's outputs are read-only; signing rewrites them in place.
chmod -R u+w "$APP"
xattr -cr "$APP"

DEVELOPER_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Developer ID Application' \
    | head -1 \
    | sed -E 's/.*"(.*)".*/\1/' || true)"
if [[ -n "$DEVELOPER_ID" ]]; then
    echo "▸ Signing with $DEVELOPER_ID…"
    codesign --force --options runtime --timestamp \
        --identifier "$FAN_HELPER_ID" --sign "$DEVELOPER_ID" "$HELPER"
    codesign --force --options runtime --timestamp \
        --identifier "$NOW_PLAYING_ADAPTER_ID" --sign "$DEVELOPER_ID" "$ADAPTER"
    codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" --sign "$DEVELOPER_ID" "$APP"
else
    echo "▸ No Developer ID identity installed; signing ad-hoc…"
    codesign --force --identifier "$FAN_HELPER_ID" --sign - "$HELPER"
    codesign --force --identifier "$NOW_PLAYING_ADAPTER_ID" --sign - "$ADAPTER"
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$HELPER"
codesign --verify --strict "$ADAPTER"
codesign --verify --deep --strict "$APP"

./Tools/notarize.sh "$APP"
./Tools/make-dmg.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="dist/Vitruvian-$VERSION.dmg"
./Tools/notarize.sh "$DMG"
echo "✓ Release DMG: $PWD/$DMG"
