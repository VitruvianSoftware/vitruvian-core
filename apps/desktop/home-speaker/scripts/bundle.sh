#!/bin/bash
# Copyright (c) 2026 VitruvianSoftware
#
# Assembles HomeSpeaker.app from a built executable.
#
#   bundle.sh <executable> <version> <output-dir>
#
# Optional env:
#   HOMESPEAKER_GOOGLE_CLIENT_ID / HOMESPEAKER_GOOGLE_CLIENT_SECRET
#       Baked into Info.plist so users can sign in without registering their
#       own Google Cloud project. Google treats desktop-app client secrets as
#       non-confidential (RFC 8252 §8.5), which is why this is safe to ship.
#   HOMESPEAKER_REQUIRE_UNIVERSAL=1
#       Fail unless the executable contains both arm64 and x86_64 slices.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

EXECUTABLE="${1:-.build/release/HomeSpeaker}"
VERSION="${2:-1.0.0}"
OUTPUT_DIR="${3:-./dist}"

APP_NAME="HomeSpeaker"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"
PLIST="${APP_BUNDLE}/Contents/Info.plist"

echo "==> Assembling ${APP_NAME}.app v${VERSION}"

if [[ "${HOMESPEAKER_REQUIRE_UNIVERSAL:-0}" == "1" ]]; then
	archs="$(lipo -archs "${EXECUTABLE}")"
	if [[ "${archs}" != *arm64* || "${archs}" != *x86_64* ]]; then
		echo "error: expected a universal binary, got: ${archs}" >&2
		exit 1
	fi
fi

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${EXECUTABLE}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

if [[ -f "${APP_DIR}/Resources/AppIcon.icns" ]]; then
	cp "${APP_DIR}/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# Resources/Info.plist is the single source of truth (release-please keeps its
# version in step with Version.swift); only the version is stamped here so a
# tag-driven package can never disagree with the tag.
cp "${APP_DIR}/Resources/Info.plist" "${PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${PLIST}"

if [[ -n "${HOMESPEAKER_GOOGLE_CLIENT_ID:-}" ]]; then
	echo "==> Embedding Google OAuth client id"
	/usr/libexec/PlistBuddy -c "Set :GoogleOAuthClientID ${HOMESPEAKER_GOOGLE_CLIENT_ID}" "${PLIST}"
	/usr/libexec/PlistBuddy -c "Set :GoogleOAuthClientSecret ${HOMESPEAKER_GOOGLE_CLIENT_SECRET:-}" "${PLIST}"
fi

echo -n "APPL????" >"${APP_BUNDLE}/Contents/PkgInfo"

# Ad-hoc signature: there is no Developer ID, so Gatekeeper will still ask the
# user to approve the first launch (see README). `--options runtime` opts into
# the hardened runtime anyway so the binary behaves like a notarized one would.
echo "==> Signing ${APP_BUNDLE} (ad-hoc, hardened runtime)"
codesign --force --deep --options runtime --sign - "${APP_BUNDLE}"
codesign --verify --deep --strict "${APP_BUNDLE}"

echo "==> ${APP_BUNDLE} successfully created"
