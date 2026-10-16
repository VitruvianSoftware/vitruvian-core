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

PLUGIN_DIR="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ -d "${PLUGIN_DIR}" ]]; then
	exec swift test -Xswiftc -plugin-path -Xswiftc "${PLUGIN_DIR}" "$@"
fi
exec swift test "$@"
