#!/bin/bash
set -euo pipefail

# bundle.sh — Assembles a proper .app bundle from a Swift PM executable
# Usage: ./bundle.sh <executable_path> <version> <output_dir>
#
# Example: ./bundle.sh .build/release/NexusAgent 1.2.0 ./dist

EXECUTABLE="${1:?Usage: bundle.sh <executable> <version> <output_dir>}"
VERSION="${2:?Missing version argument}"
OUTPUT_DIR="${3:?Missing output directory}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCES_DIR="${SCRIPT_DIR}/../Resources"
APP_NAME="NexusAgent"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"

echo "==> Assembling ${APP_NAME}.app v${VERSION}"

# Clean and create bundle structure
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executable
cp "${EXECUTABLE}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Copy icon
if [ -f "${RESOURCES_DIR}/AppIcon.icns" ]; then
    cp "${RESOURCES_DIR}/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"
    echo "    ✓ Icon copied"
fi

# Generate Info.plist with correct version
cat > "${APP_BUNDLE}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.vitruviansoftware.nexusagent</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
</dict>
</plist>
EOF

echo "    ✓ Info.plist generated"

# Create PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# Ad-hoc sign the bundle to prevent "App is damaged" errors
echo "==> Signing ${APP_BUNDLE} with ad-hoc signature"
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> ${APP_BUNDLE} ready"
