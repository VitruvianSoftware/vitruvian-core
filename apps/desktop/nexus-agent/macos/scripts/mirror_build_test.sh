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
#
# It then runs the tests with SwiftPM too. The copy is laid out as the mirror
# is, `macos/` beside `testdata/`, because the tests find the shared examples
# from their own file's path.
set -euo pipefail

app="$TEST_SRCDIR/$TEST_WORKSPACE/apps/desktop/nexus-agent"
work="$TEST_TMPDIR/mirror/macos"
mkdir -p "$work"
cp -RL "$app/macos/Package.swift" "$app/macos/Sources" "$app/macos/Tests" "$work/"
cp -RL "$app/testdata" "$TEST_TMPDIR/mirror/"

export HOME="$TEST_TMPDIR/home"
mkdir -p "$HOME"
xcrun swift build --package-path "$work" --scratch-path "$TEST_TMPDIR/build" \
	--cache-path "$TEST_TMPDIR/cache" --disable-sandbox

# Without Bazel's two variables, so the tests look where they do on the mirror
# and not in this test's runfiles. CFFIXED_USER_HOME moves the home Foundation
# reports as well: HOME alone does not.
log="$TEST_TMPDIR/swift-test.log"
if ! env -u TEST_SRCDIR -u TEST_WORKSPACE CFFIXED_USER_HOME="$HOME" \
	xcrun swift test --package-path "$work" --scratch-path "$TEST_TMPDIR/build" \
	--cache-path "$TEST_TMPDIR/cache" --disable-sandbox >"$log" 2>&1; then
	cat "$log"
	exit 1
fi

# A run that found no tests also exits 0: require that some ran.
summary="$(grep -E 'Executed [0-9]+ tests?, with 0 failures' "$log" | tail -n 1 || true)"
echo "swift test: ${summary:-no summary line}"
if ! grep -qE 'Executed [1-9][0-9]* tests?, with 0 failures' <<<"$summary"; then
	cat "$log"
	echo "swift test ran no tests" >&2
	exit 1
fi
