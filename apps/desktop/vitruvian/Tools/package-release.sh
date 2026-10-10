#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

# Turns the Bazel-built app into the release DMG, dist/Vitruvian-<version>.dmg:
#   bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian
#   apps/desktop/vitruvian/Tools/package-release.sh "$PWD/<path to Vitruvian.zip>"
#
# It unpacks the bundle into a temp dir (never a "build" directory, which on
# macOS's case-insensitive filesystem is the package's Bazel BUILD file) and
# signs the fan helper, the Now Playing adapter, the GravaStar mouse command
# (Contents/Helpers) and the bundle, as build.sh signs the first two and the
# bundle: with the Developer ID identity when one is installed
# (Tools/ci-setup-signing.sh imports it on CI), ad-hoc otherwise. It notarizes
# the app and the DMG when the notary credentials are set (Tools/notarize.sh
# skips quietly when they are not), and packages the DMG with Tools/make-dmg.sh.
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
MOUSE_TOOL_ID="$APP_BUNDLE_ID.gravastar-mouse"
ENTITLEMENTS="Resources/Vitruvian.entitlements"
STAGE=""
cleanup() {
    [[ -n "$STAGE" ]] && rm -rf "$STAGE"
}
trap cleanup EXIT
STAGE="$(mktemp -d)"
APP="$STAGE/Vitruvian.app"
HELPER="$APP/Contents/Library/LaunchServices/$FAN_HELPER_ID"
ADAPTER="$APP/Contents/Frameworks/libVitruvianNowPlaying.dylib"
MOUSE_TOOL="$APP/Contents/Helpers/gravastar-mouse"

echo "▸ Unpacking $ARCHIVE…"
ditto -x -k "$ARCHIVE" "$STAGE"
for part in "$APP" "$HELPER" "$ADAPTER" "$MOUSE_TOOL"; do
    if [[ ! -e "$part" ]]; then
        echo "✗ $part is missing from the archive" >&2
        exit 1
    fi
done
# Bazel's outputs are read-only; signing rewrites them in place.
chmod -R u+w "$APP"
find "$APP" -exec xattr -c {} + 2>/dev/null || true

DEVELOPER_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Developer ID Application' \
    | head -1 \
    | sed -E 's/.*"(.*)".*/\1/' || true)"

sign_bundle() {
    local target_app="$1"
    local helper="$target_app/Contents/Library/LaunchServices/$FAN_HELPER_ID"
    local adapter="$target_app/Contents/Frameworks/libVitruvianNowPlaying.dylib"
    local mouse_tool="$target_app/Contents/Helpers/gravastar-mouse"

    chmod -R u+w "$target_app"
    find "$target_app" -exec xattr -c {} + 2>/dev/null || true

    if [[ -n "$DEVELOPER_ID" ]]; then
        echo "▸ Signing with $DEVELOPER_ID…"
        codesign --force --options runtime --timestamp \
            --identifier "$FAN_HELPER_ID" --sign "$DEVELOPER_ID" "$helper"
        codesign --force --options runtime --timestamp \
            --identifier "$NOW_PLAYING_ADAPTER_ID" --sign "$DEVELOPER_ID" "$adapter"
        codesign --force --options runtime --timestamp \
            --identifier "$MOUSE_TOOL_ID" --sign "$DEVELOPER_ID" "$mouse_tool"
        codesign --force --options runtime --timestamp \
            --entitlements "$ENTITLEMENTS" --sign "$DEVELOPER_ID" "$target_app"
    else
        echo "▸ No Developer ID identity installed; signing ad-hoc…"
        codesign --force --identifier "$FAN_HELPER_ID" --sign - "$helper"
        codesign --force --identifier "$NOW_PLAYING_ADAPTER_ID" --sign - "$adapter"
        codesign --force --identifier "$MOUSE_TOOL_ID" --sign - "$mouse_tool"
        codesign --force --sign - "$target_app"
    fi
    codesign --verify --strict "$helper"
    codesign --verify --strict "$adapter"
    codesign --verify --strict "$mouse_tool"
    codesign --verify --deep --strict "$target_app"
}

# Sign and notarize universal bundle
sign_bundle "$APP"
./Tools/notarize.sh "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
mkdir -p dist

echo "▸ Packaging Universal DMG & ZIP…"
./Tools/make-dmg.sh "$APP" "dist/Vitruvian-$VERSION-universal.dmg"
cp -f "dist/Vitruvian-$VERSION-universal.dmg" "dist/Vitruvian-$VERSION.dmg"
rm -f "dist/Vitruvian-$VERSION-universal.zip"
ditto -c -k --keepParent "$APP" "dist/Vitruvian-$VERSION-universal.zip"

echo "▸ Thinning and packaging Apple Silicon (arm64) DMG…"
STAGE_ARM64="$STAGE/arm64"
mkdir -p "$STAGE_ARM64"
ditto "$APP" "$STAGE_ARM64/Vitruvian.app"
APP_ARM64="$STAGE_ARM64/Vitruvian.app"
for bin in "$APP_ARM64/Contents/MacOS/Vitruvian" \
           "$APP_ARM64/Contents/Library/LaunchServices/$FAN_HELPER_ID" \
           "$APP_ARM64/Contents/Frameworks/libVitruvianNowPlaying.dylib" \
           "$APP_ARM64/Contents/Helpers/gravastar-mouse"; do
    if lipo -info "$bin" | grep -q "arm64"; then
        lipo "$bin" -thin arm64 -output "$bin"
    fi
done
sign_bundle "$APP_ARM64"
./Tools/notarize.sh "$APP_ARM64"
./Tools/make-dmg.sh "$APP_ARM64" "dist/Vitruvian-$VERSION-arm64.dmg"

echo "▸ Thinning and packaging Intel (x86_64) DMG…"
STAGE_X86_64="$STAGE/x86_64"
mkdir -p "$STAGE_X86_64"
ditto "$APP" "$STAGE_X86_64/Vitruvian.app"
APP_X86_64="$STAGE_X86_64/Vitruvian.app"
for bin in "$APP_X86_64/Contents/MacOS/Vitruvian" \
           "$APP_X86_64/Contents/Library/LaunchServices/$FAN_HELPER_ID" \
           "$APP_X86_64/Contents/Frameworks/libVitruvianNowPlaying.dylib" \
           "$APP_X86_64/Contents/Helpers/gravastar-mouse"; do
    if lipo -info "$bin" | grep -q "x86_64"; then
        lipo "$bin" -thin x86_64 -output "$bin"
    fi
done
sign_bundle "$APP_X86_64"
./Tools/notarize.sh "$APP_X86_64"
./Tools/make-dmg.sh "$APP_X86_64" "dist/Vitruvian-$VERSION-x86_64.dmg"

echo "▸ Notarizing DMGs…"
./Tools/notarize.sh "dist/Vitruvian-$VERSION-universal.dmg"
./Tools/notarize.sh "dist/Vitruvian-$VERSION-arm64.dmg"
./Tools/notarize.sh "dist/Vitruvian-$VERSION-x86_64.dmg"
./Tools/notarize.sh "dist/Vitruvian-$VERSION.dmg"

echo "✓ Release artifacts ready in dist/:"
ls -lh dist/Vitruvian-$VERSION*
