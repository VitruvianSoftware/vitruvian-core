#!/bin/bash
# Copyright (c) 2026 VitruvianSoftware
#
# Runs the swift-testing suite. The Command Line Tools toolchain ships the
# Testing macro plugin outside the compiler's default search path, so a bare
# `swift test` fails with "plugin for module 'TestingMacros' not found".

set -euo pipefail

# A Beeper address on this Mac that nothing listens on (port 9, discard): a
# test that turns Beeper on and forgets its stand-in fails to connect,
# rather than sending a token to the real Beeper Desktop on 23373.
export HOMESPEAKER_BEEPER_URL="http://localhost:9"

DEV_DIR="$(xcode-select -p)"
PLUGIN_DIR="${DEV_DIR}/usr/lib/swift/host/plugins/testing"
PLATFORM_DEV="${DEV_DIR}/Platforms/MacOSX.platform/Developer"
# `/usr/bin/perl` is a platform binary, so macOS strips DYLD_FRAMEWORK_PATH
# when PerlNowPlayingRunner spawns it to dlopen the test bundle. Bake the
# platform framework/library search paths into the test binary's LC_RPATH
# (as Bazel's swift_test already does).
RPATH_FLAGS=()
if [[ -d "${PLATFORM_DEV}/Library/Frameworks" ]]; then
	RPATH_FLAGS+=(-Xlinker -rpath -Xlinker "${PLATFORM_DEV}/Library/Frameworks")
fi
if [[ -d "${PLATFORM_DEV}/usr/lib" ]]; then
	RPATH_FLAGS+=(-Xlinker -rpath -Xlinker "${PLATFORM_DEV}/usr/lib")
fi
if [[ -d "${PLUGIN_DIR}" ]]; then
	exec swift test "${RPATH_FLAGS[@]}" -Xswiftc -plugin-path -Xswiftc "${PLUGIN_DIR}" "$@"
fi
exec swift test "${RPATH_FLAGS[@]}" "$@"
