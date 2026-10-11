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

set -euo pipefail

SCRIPT_UNDER_TEST="${1:-tools/desktop-package/package-desktop.sh}"
if [[ ! -f "$SCRIPT_UNDER_TEST" ]]; then
  # Check if in runfiles
  if [[ -f "${TEST_SRCDIR}/_main/tools/desktop-package/package-desktop.sh" ]]; then
    SCRIPT_UNDER_TEST="${TEST_SRCDIR}/_main/tools/desktop-package/package-desktop.sh"
  elif [[ -f "${BASH_SOURCE[0]%/*}/package-desktop.sh" ]]; then
    SCRIPT_UNDER_TEST="${BASH_SOURCE[0]%/*}/package-desktop.sh"
  fi
fi

# 1. Source pure library
PACKAGE_DESKTOP_LIB_ONLY=1 . "$SCRIPT_UNDER_TEST"

ok() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

echo "=== Running unit tests for package-desktop pure helpers ==="

# Test clean_version
v1="$(clean_version "home-speaker-v1.11.0")"
[[ "$v1" == "1.11.0" ]] || fail "clean_version failed for home-speaker tag: got $v1"
ok "clean_version home-speaker-v1.11.0 -> 1.11.0"

v2="$(clean_version "vitruvian-v3.37.1")"
[[ "$v2" == "3.37.1" ]] || fail "clean_version failed for vitruvian tag: got $v2"
ok "clean_version vitruvian-v3.37.1 -> 3.37.1"

v3="$(clean_version "nexus-agent-v1.20.1")"
[[ "$v3" == "1.20.1" ]] || fail "clean_version failed for nexus-agent tag: got $v3"
ok "clean_version nexus-agent-v1.20.1 -> 1.20.1"

v4="$(clean_version "v2.0.4")"
[[ "$v4" == "2.0.4" ]] || fail "clean_version failed for v-tag: got $v4"
ok "clean_version v2.0.4 -> 2.0.4"

v5="$(clean_version "4.5.6")"
[[ "$v5" == "4.5.6" ]] || fail "clean_version failed for raw semver: got $v5"
ok "clean_version 4.5.6 -> 4.5.6"

v6="$(clean_version "nexus-agent-1.20.1")"
[[ "$v6" == "1.20.1" ]] || fail "clean_version failed for tag without v prefix: got $v6"
ok "clean_version nexus-agent-1.20.1 -> 1.20.1"

v7="$(clean_version "vitruvian-v3.38.0-beta.1")"
[[ "$v7" == "3.38.0-beta.1" ]] || fail "clean_version failed for prerelease: got $v7"
ok "clean_version vitruvian-v3.38.0-beta.1 -> 3.38.0-beta.1"

# Test cask_name_for_app
c1="$(cask_name_for_app "HomeSpeaker")"
[[ "$c1" == "home-speaker" ]] || fail "cask_name_for_app HomeSpeaker failed: got $c1"
ok "cask_name_for_app HomeSpeaker -> home-speaker"

c2="$(cask_name_for_app "NexusAgent")"
[[ "$c2" == "nexus-agent" ]] || fail "cask_name_for_app NexusAgent failed: got $c2"
ok "cask_name_for_app NexusAgent -> nexus-agent"

c3="$(cask_name_for_app "Vitruvian")"
[[ "$c3" == "vitruvian" ]] || fail "cask_name_for_app Vitruvian failed: got $c3"
ok "cask_name_for_app Vitruvian -> vitruvian"

c4="$(cask_name_for_app "MyNewDesktopClient")"
[[ "$c4" == "my-new-desktop-client" ]] || fail "cask_name_for_app MyNewDesktopClient failed: got $c4"
ok "cask_name_for_app MyNewDesktopClient -> my-new-desktop-client"

# Test expected_artifact_names
artifacts="$(expected_artifact_names "TestApp" "1.0.0")"
echo "$artifacts" | grep -q "^TestApp-1.0.0-universal.dmg$" || fail "missing universal dmg in expected artifacts"
echo "$artifacts" | grep -q "^TestApp-1.0.0-arm64.dmg$" || fail "missing arm64 dmg in expected artifacts"
echo "$artifacts" | grep -q "^TestApp-1.0.0-x86_64.dmg$" || fail "missing x86_64 dmg in expected artifacts"
echo "$artifacts" | grep -q "^TestApp-1.0.0-universal.zip$" || fail "missing universal zip in expected artifacts"
echo "$artifacts" | grep -q "^TestApp-1.0.0.dmg$" || fail "missing legacy dmg in expected artifacts"
ok "expected_artifact_names produces complete 5-item artifact matrix"

# Test generate_cask_ruby
ruby_cask="$(generate_cask_ruby "test-app" "1.0.0" "fake_sha256" "https://example.com/TestApp-1.0.0-universal.dmg" "TestApp" "A test app" "https://example.com")"

echo "$ruby_cask" | grep -q 'cask "test-app" do' || fail "cask declaration missing"
echo "$ruby_cask" | grep -q 'version "1.0.0"' || fail "version declaration missing"
echo "$ruby_cask" | grep -q 'sha256 "fake_sha256"' || fail "sha256 declaration missing"
echo "$ruby_cask" | grep -q 'url "https://example.com/TestApp-1.0.0-universal.dmg"' || fail "url declaration missing"
echo "$ruby_cask" | grep -q 'name "TestApp"' || fail "name declaration missing"
echo "$ruby_cask" | grep -q 'desc "A test app"' || fail "desc declaration missing"
echo "$ruby_cask" | grep -q 'homepage "https://example.com"' || fail "homepage declaration missing"
echo "$ruby_cask" | grep -q 'app "TestApp.app"' || fail "app bundle declaration missing"
ok "generate_cask_ruby generates valid Homebrew Cask specification"

# Test dry-run packaging flow with mock app
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

MOCK_APP="$TMP_DIR/MockApp.app"
mkdir -p "$MOCK_APP/Contents/MacOS"
mkdir -p "$MOCK_APP/Contents/Resources"
echo "#!/bin/sh" > "$MOCK_APP/Contents/MacOS/MockApp"
chmod +x "$MOCK_APP/Contents/MacOS/MockApp"
cat > "$MOCK_APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MockApp</string>
    <key>CFBundleShortVersionString</key>
    <string>2.3.4</string>
</dict>
</plist>
EOF

MOCK_DIST="$TMP_DIR/dist"
mkdir -p "$MOCK_DIST"

echo "==> Executing CLI dry-run package test..."
bash "$SCRIPT_UNDER_TEST" \
  --app-path "$MOCK_APP" \
  --dist-dir "$MOCK_DIST" \
  --version "2.3.4" \
  --skip-signing \
  --skip-dmg \
  --dry-run

[[ -f "$MOCK_DIST/MockApp-2.3.4-universal.zip" ]] || fail "universal zip was not created"
[[ -f "$MOCK_DIST/MockApp-2.3.4-universal.zip.sha256" ]] || fail "universal zip checksum was not created"

# Verify that the checksum file uses relative filename and shasum -c succeeds
(cd "$MOCK_DIST" && shasum -c "MockApp-2.3.4-universal.zip.sha256") >/dev/null 2>&1 || fail "shasum -c failed on generated sidecar"
ok "shasum -c validation succeeded on artifact sidecar"

[[ -f "$MOCK_DIST/mock-app.rb" ]] || fail "cask formula mock-app.rb was not created"

grep -q 'version "2.3.4"' "$MOCK_DIST/mock-app.rb" || fail "mock-app.rb missing version"
grep -q 'app "MockApp.app"' "$MOCK_DIST/mock-app.rb" || fail "mock-app.rb missing app bundle"

ok "CLI dry run produced valid universal zip, checksum sidecar, and Cask formula"
echo "All package-desktop tests passed successfully!"
