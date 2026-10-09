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

# Builds the package with SwiftPM, the way VitruvianSoftware/nexus-agent does.
# Bazel is the build this repository runs, so a target missing from
# Package.swift stayed green here while every mirror release failed
# (2026-07-11 to 2026-08-20, #1511, #1851). This fails here instead.
set -euo pipefail

pkg="$TEST_SRCDIR/$TEST_WORKSPACE/apps/desktop/nexus-agent/macos"
work="$TEST_TMPDIR/pkg"
mkdir -p "$work"
cp -RL "$pkg/Package.swift" "$pkg/Sources" "$work/"

export HOME="$TEST_TMPDIR/home"
mkdir -p "$HOME"
xcrun swift build --package-path "$work" --scratch-path "$TEST_TMPDIR/build" \
    --cache-path "$TEST_TMPDIR/cache" --disable-sandbox
