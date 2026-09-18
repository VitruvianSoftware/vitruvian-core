#!/bin/bash
# Copyright (c) 2026 VitruvianSoftware
#
# Runs the swift-testing suite. The Command Line Tools toolchain ships the
# Testing macro plugin outside the compiler's default search path, so a bare
# `swift test` fails with "plugin for module 'TestingMacros' not found".

set -euo pipefail

PLUGIN_DIR="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ -d "${PLUGIN_DIR}" ]]; then
    exec swift test -Xswiftc -plugin-path -Xswiftc "${PLUGIN_DIR}" "$@"
fi
exec swift test "$@"
