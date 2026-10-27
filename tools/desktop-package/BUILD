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

"""Reusable release packaging and distribution tooling for macOS desktop applications."""

# Hand-written: gazelle would generate targets for the package.
# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# The crate takes std only. Optimised in every build mode.
rust_library(
    name = "package_desktop_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = [
            "src/main.rs",
            "src/probe.rs",
        ],
    ),
    crate_name = "package_desktop",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "package-desktop",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":package_desktop_lib"],
)

# Generated launcher so any Bazel target referencing
# `//tools/desktop-package:package-desktop.sh` resolves to the Rust binary.
genrule(
    name = "package_desktop_sh_shim",
    srcs = [":package-desktop"],
    outs = ["package-desktop.sh"],
    cmd = "printf '%s\\n' '#!/usr/bin/env bash' 'exec \"$$(cd \"$$(dirname \"$${BASH_SOURCE[0]}\")\" && pwd)/package-desktop\" \"$$@\"' > $@ && chmod +x $@",
    executable = True,
    visibility = ["//visibility:public"],
)

alias(
    name = "package_desktop",
    actual = ":package-desktop",
    visibility = ["//visibility:public"],
)

alias(
    name = "package-desktop-rs",
    actual = ":package-desktop",
    visibility = ["//visibility:public"],
)

alias(
    name = "package_desktop_rs",
    actual = ":package-desktop",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "package_desktop_lib_test",
    size = "small",
    crate = ":package_desktop_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "package-desktop_test",
    tests = [":package_desktop_lib_test"],
)

test_suite(
    name = "package-desktop-rs_test",
    tests = [":package_desktop_lib_test"],
)
