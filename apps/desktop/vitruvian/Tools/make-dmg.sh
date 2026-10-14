#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Packages a signed app into a styled, distributable DMG
# (dist/Vitruvian-<version>.dmg): a window with the app icon, an arrow and
# the Applications folder for drag-and-drop install.
#   Tools/make-dmg.sh <absolute path to the signed Vitruvian.app>
# Tools/package-release.sh calls it. Nothing here writes into a "build"
# directory: on macOS's case-insensitive filesystem that name is the package's
# Bazel BUILD file, so the background renders into this script's own temp dir.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Vitruvian"
APP="${1:-}"
if [[ -z "$APP" ]]; then
    echo "usage: make-dmg.sh <path to the signed $APP_NAME.app>" >&2
    exit 1
fi
VOLUME="$APP_NAME"
STAGING=""
WORK=""
MOUNT=""

cleanup() {
    if [[ -n "$MOUNT" ]]; then
        hdiutil detach "$MOUNT" -quiet 2>/dev/null \
            || hdiutil detach "$MOUNT" -force -quiet 2>/dev/null \
            || true
    fi
    [[ -n "$STAGING" ]] && rm -rf "$STAGING"
    [[ -n "$WORK" ]] && rm -rf "$WORK"
}
trap cleanup EXIT

if [[ ! -d "$APP" ]]; then
    echo "✗ $APP not found" >&2
    exit 1
fi
find "$APP" -exec xattr -c {} + 2>/dev/null || true
codesign --verify --deep --strict "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUT="${2:-dist/Vitruvian-$VERSION.dmg}"

WORK="$(mktemp -d)"
BACKGROUND="$WORK/dmg-background.png"

echo "▸ Rendering installer background…"
swift Tools/MakeDMGBackground.swift "$BACKGROUND"

echo "▸ Staging DMG contents…"
STAGING="$(mktemp -d)"
ditto "$APP" "$STAGING/$APP_NAME.app"
find "$STAGING/$APP_NAME.app" -exec xattr -c {} + 2>/dev/null || true
codesign --verify --deep --strict "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
mkdir "$STAGING/.background"
cp "$BACKGROUND" "$STAGING/.background/background.png"

echo "▸ Creating writable image…"
# Detaches every attachment of one image, found by the image's path. It reaches
# an attachment that has no mount point and whose device nobody recorded.
release_image() {
    local device
    for device in $(hdiutil info | sh Tools/dmg-image-devices.sh "$1"); do
        hdiutil detach "$device" -force || true
    done
}
# Clear any stale mount left by a previous attempt on the same runner.
hdiutil detach "/Volumes/$VOLUME" -force 2>/dev/null || true
# hdiutil can fail transiently on CI runners; retry a few times. No -quiet, so a
# real error is visible in the build log rather than swallowed.
#
# A create that fails with "Resource busy" can leave its half-made image
# attached. Each attempt therefore writes its own file, so a leftover from a
# failed attempt is never mistaken for the image being packaged, and the
# leftover is detached before the next attempt.
created=0
for attempt in 1 2 3; do
    RW="$WORK/rw-$attempt.dmg"
    if hdiutil create -volname "$VOLUME" -srcfolder "$STAGING" -fs HFS+ -format UDRW -ov "$RW"; then
        created=1
        break
    fi
    echo "  hdiutil create failed (attempt $attempt of 3), retrying…" >&2
    release_image "$RW"
    rm -f "$RW"
    sleep 3
done
if [[ $created -ne 1 ]]; then
    echo "✗ Could not create the disk image after 3 attempts" >&2
    exit 1
fi
ATTACH_OUTPUT="$(hdiutil attach "$RW" -nobrowse)"
MOUNT="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/\/Volumes\// {print substr($0, index($0, "/Volumes/")); exit}')"
if [[ -z "$MOUNT" || ! -d "$MOUNT" ]]; then
    echo "✗ Could not find mounted volume in hdiutil output" >&2
    printf '%s\n' "$ATTACH_OUTPUT" >&2
    exit 1
fi

echo "▸ Arranging window (icons, arrow, background)…"
# Finder automation lays out the window; best-effort so a headless hiccup never
# fails the release (the DMG is still valid, just unstyled that once).
osascript <<APPLESCRIPT &
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 800, 520}
        set theOptions to the icon view options of container window
        set arrangement of theOptions to not arranged
        set icon size of theOptions to 128
        set text size of theOptions to 13
        set background picture of theOptions to file ".background:background.png"
        set position of item "$APP_NAME.app" of container window to {150, 200}
        set position of item "Applications" of container window to {450, 200}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
STYLE_PID=$!
STYLE_STATUS=0
STYLE_TIMED_OUT=0
for _ in {1..25}; do
    if ! kill -0 "$STYLE_PID" 2>/dev/null; then
        wait "$STYLE_PID" || STYLE_STATUS=$?
        break
    fi
    sleep 1
done
if kill -0 "$STYLE_PID" 2>/dev/null; then
    STYLE_TIMED_OUT=1
    kill "$STYLE_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$STYLE_PID" 2>/dev/null || true
    wait "$STYLE_PID" 2>/dev/null || true
fi
if (( STYLE_TIMED_OUT )); then
    echo "  (window styling timed out; continuing with a valid unstyled DMG)"
elif (( STYLE_STATUS != 0 )); then
    echo "  (window styling skipped)"
fi

sync
# Finder can keep the volume busy for a moment after its window closes, and a
# busy volume refuses to detach, forced or not. Retry before forcing; no
# -quiet, so a real failure says why in the build log.
detached=0
for attempt in 1 2 3 4; do
    if hdiutil detach "$MOUNT"; then
        detached=1
        break
    fi
    # A detach that reported "Resource busy" can still finish a moment later.
    # Once the mount is gone there is nothing left to detach, and asking again
    # fails with "No such file or directory", which is not a failure.
    if [[ ! -d "$MOUNT" ]]; then
        detached=1
        break
    fi
    echo "  hdiutil detach failed (attempt $attempt of 4), retrying…" >&2
    sleep 2
done
if [[ $detached -ne 1 && -d "$MOUNT" ]]; then
    hdiutil detach "$MOUNT" -force
fi
MOUNT=""

# The mount point can vanish while the image is still attached, and converting
# an attached image fails. Wait until the image itself is released.
for _ in $(seq 1 5); do
    hdiutil info | grep -qF "$RW" || break
    sleep 2
done
# Still attached with the mount folder gone: a detach by path has nothing to
# act on, so release the image by its device nodes, forced.
if hdiutil info | grep -qF "$RW"; then
    for attempt in 1 2 3 4 5; do
        release_image "$RW"
        hdiutil info | grep -qF "$RW" || break
        echo "  image still attached after forced detach (attempt $attempt of 5), retrying…" >&2
        sleep 3
    done
fi
if hdiutil info | grep -qF "$RW"; then
    echo "✗ The disk image is still attached and cannot be compressed" >&2
    hdiutil info >&2 || true
    exit 1
fi

echo "▸ Compressing…"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
# No -quiet, so a failure says why; a convert can lose a race with a late
# detach, so try again before giving up.
converted=0
for attempt in 1 2 3; do
    if hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT"; then
        converted=1
        break
    fi
    echo "  hdiutil convert failed (attempt $attempt of 3), retrying…" >&2
    rm -f "$OUT"
    sleep 5
done
if [[ $converted -ne 1 ]]; then
    echo "✗ Could not compress the disk image after 3 attempts" >&2
    exit 1
fi

echo "✓ DMG ready: $OUT"
