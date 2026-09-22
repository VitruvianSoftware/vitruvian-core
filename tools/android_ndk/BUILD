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

load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

# Hermetic Android NDK toolchain. See extension.bzl.

bzl_library(
    name = "extension",
    srcs = ["extension.bzl"],
    visibility = ["//visibility:public"],
    # keep: gazelle infers @rules_android_ndk//:rules from the load in
    # extension.bzl, but that module ships no bzl_library, so the target does
    # not exist and every Bazel invocation in the repo fails to analyse.
    deps = [],
)

# The patch lives beside the extension that depends on it, rather than in a
# third_party/ root the conformance taxonomy disallows.
exports_files(["hermetic_ndk.patch"])
