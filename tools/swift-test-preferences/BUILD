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

# //tools/swift-test-preferences: keeps the UserDefaults suites Swift tests open
# out of the developer's real ~/Library/Preferences. On 2026-11-02 some 56,000
# leftover test suites there had stopped macOS saving any app's preferences.
# Load `swift_test` from :defs.bzl; it links :test_preferences into the test,
# which saves the test's preferences under its own TEST_TMPDIR instead.
# gazelle:ignore

load("@rules_cc//cc:defs.bzl", "cc_library")
load("//tools/apple:defs.bzl", "APPLE_TOOLCHAIN_ONLY")
load(":defs.bzl", "swift_test")

cc_library(
    name = "test_preferences",
    srcs = ["test_preferences.c"],
    linkopts = [
        "-framework",
        "CoreFoundation",
        "-framework",
        "Foundation",
    ],
    target_compatible_with = ["@platforms//os:macos"],
    visibility = ["//visibility:public"],
    # Nothing calls into it: it works from a constructor, which the linker
    # would otherwise drop.
    alwayslink = True,
)

# Proves it: what a test saves lands under TEST_TMPDIR, and nothing reaches the
# account's real preferences folder.
swift_test(
    name = "TestPreferencesTests",
    size = "small",
    srcs = ["Tests/TestPreferencesTests.swift"],
    tags = ["manual"],
    target_compatible_with = APPLE_TOOLCHAIN_ONLY,
)
