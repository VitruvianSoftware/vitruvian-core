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

load("@wand_crates//:defs.bzl", "all_crate_deps")
load(
    "//apps/suites/wand/build:defs.bzl",
    "wand_rust_binary",
    "wand_rust_library",
    "wand_rust_shared_library",
    "wand_rust_test",
)

package(default_visibility = ["//apps/suites/wand:__subpackages__"])

_DEPS = all_crate_deps(normal = True)

_PROC_MACRO_DEPS = all_crate_deps(proc_macro = True)

wand_rust_library(
    name = "smoke",
    srcs = ["src/lib.rs"],
    crate_name = "wand_build_smoke",
    proc_macro_deps = _PROC_MACRO_DEPS,
    deps = _DEPS,
)

wand_rust_binary(
    name = "smoke_bin",
    srcs = ["src/main.rs"],
    deps = [":smoke"] + _DEPS,
)

wand_rust_test(
    name = "smoke_test",
    size = "small",
    crate = ":smoke",
    proc_macro_deps = _PROC_MACRO_DEPS,
    deps = _DEPS,
)

wand_rust_shared_library(
    name = "smoke_jni",
    srcs = ["src/lib.rs"],
    crate_name = "wand_build_smoke_jni",
    proc_macro_deps = _PROC_MACRO_DEPS,
    target_compatible_with = ["@platforms//os:android"],
    deps = _DEPS,
)
