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

"""Compatibility for targets that compile Swift or Objective-C."""

# Use as `target_compatible_with = APPLE_TOOLCHAIN_ONLY` on swift_library,
# swift_binary, swift_test and macos_application. With --config=macos-app the
# target builds on macOS exactly as before. Without it -- a plain
# `bazel build //...` on a Mac, or any Linux build -- the target and everything
# that depends on it are skipped as incompatible instead of failing to compile.
APPLE_TOOLCHAIN_ONLY = select({
    "//tools/apple:apple_cc_toolchain": ["@platforms//os:macos"],
    "//conditions:default": ["@platforms//:incompatible"],
})
