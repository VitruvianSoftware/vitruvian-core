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

rust_library(
    name = "design_sync_lib",
    srcs = [
        "src/inject_reference_fonts.rs",
        "src/lib.rs",
        "src/mcp_slack_e2e.rs",
        "src/prepare.rs",
    ],
    crate_name = "design_sync_lib",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "inject_reference_fonts",
    srcs = ["src/bin/inject_reference_fonts.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":design_sync_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

alias(
    name = "inject-reference-fonts",
    actual = ":inject_reference_fonts",
    visibility = ["//visibility:public"],
)

alias(
    name = "inject-reference-fonts-rs",
    actual = ":inject_reference_fonts",
    visibility = ["//visibility:public"],
)

rust_binary(
    name = "prepare",
    srcs = ["src/bin/prepare.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":design_sync_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

alias(
    name = "prepare-rs",
    actual = ":prepare",
    visibility = ["//visibility:public"],
)

rust_binary(
    name = "test_mcp_slack_e2e",
    srcs = ["src/bin/test_mcp_slack_e2e.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":design_sync_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

alias(
    name = "test-mcp-slack-e2e",
    actual = ":test_mcp_slack_e2e",
    visibility = ["//visibility:public"],
)

alias(
    name = "test-mcp-slack-e2e-rs",
    actual = ":test_mcp_slack_e2e",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "design_sync_lib_test",
    size = "small",
    crate = ":design_sync_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "sync_test",
    tests = [":design_sync_lib_test"],
)

test_suite(
    name = "design_sync_test",
    tests = [":design_sync_lib_test"],
)
