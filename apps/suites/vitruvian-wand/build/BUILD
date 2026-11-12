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

# gazelle:ignore

load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

package(default_visibility = ["//apps/suites/vitruvian-wand:__subpackages__"])

bzl_library(
    name = "defs",
    srcs = ["defs.bzl"],
    deps = [
        "@rules_cc//cc/common",
        "@rules_rust//rust:bzl_lib",
    ],
)

sh_binary(
    name = "lock",
    srcs = ["lock.sh"],
    data = [
        "//tools/crates:lock",
        "//tools/crates:relock_cargo",
    ],
    env = {
        "CRATES_LOCK_BIN": "$(rootpath //tools/crates:lock)",
        "RELOCK_CARGO": "$(rootpath //tools/crates:relock_cargo)",
    },
)
