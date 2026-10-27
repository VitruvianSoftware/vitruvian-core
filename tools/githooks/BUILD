# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
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

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

exports_files([
    "pre-commit",
])

sh_binary(
    name = "pre-commit-sh",
    srcs = ["pre-commit"],
    visibility = ["//visibility:public"],
)

rust_library(
    name = "githooks_lib",
    srcs = [
        "src/check_config.rs",
        "src/lib.rs",
        "src/pre_commit.rs",
    ],
    crate_name = "githooks_lib",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_binary(
    name = "check_config",
    srcs = ["src/bin/check_config.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":githooks_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

alias(
    name = "check-config",
    actual = ":check_config",
    visibility = ["//visibility:public"],
)

alias(
    name = "check-config-rs",
    actual = ":check_config",
    visibility = ["//visibility:public"],
)

rust_binary(
    name = "pre_commit",
    srcs = ["src/bin/pre_commit.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":githooks_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

alias(
    name = "pre-commit-rs",
    actual = ":pre_commit",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "githooks_lib_test",
    size = "small",
    crate = ":githooks_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "githooks_test",
    tests = [":githooks_lib_test"],
)

test_suite(
    name = "check_config_test",
    tests = [":githooks_lib_test"],
)
