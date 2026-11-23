# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Python's string, error, json and argparse behaviour for the Rust ports of Python tools.

No third-party crates, so any tool can link it whatever crate hub it uses.
"""

load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

rust_library(
    name = "vitruvian_pycompat",
    srcs = glob(["src/**/*.rs"]),
    crate_name = "vitruvian_pycompat",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
)

rust_test(
    name = "vitruvian_pycompat_test",
    size = "small",
    crate = ":vitruvian_pycompat",
    data = ["testdata/json_golden.jsonl"],
)

# Sources and plain-rustc build helper, for //tools/ci:build_ci_tool_test.
filegroup(
    name = "srcs",
    srcs = glob(["src/**/*.rs"]) + ["rustc-build.sh"],
    visibility = ["//tools/ci:__pkg__"],
)

# rustc-build.sh is the out-of-Bazel build the scheduled workflows,
# package-desktop and build-ci-tool use; this test runs it the way they do.
sh_test(
    name = "rustc_build_test",
    size = "medium",
    srcs = ["rustc_build_test.sh"],
    data = glob(["src/**/*.rs"]) + [
        "rustc-build.sh",
        "//catalog:srcs",
        "//packages/jq:srcs",
        "//tools/agent-app:rust_sources",
        "//tools/gitops/appset-render:srcs",
        "//tools/osv-scan:rust_sources",
        "//tools/pipeline-status:rust_sources",
        "//tools/release-scope:rust_sources",
        "//tools/sync-downloads:rust_sources",
        "@rules_rust//rust/toolchain:current_rust_stdlib_files",
        "@rules_rust//rust/toolchain:current_rust_toolchain",
        "@rules_rust//rust/toolchain:current_rustc_files",
        "@rules_rust//rust/toolchain:current_rustc_lib_files",
    ],
    env = {"REAL_RUSTC": "$(rootpath @rules_rust//rust/toolchain:current_rustc_files)"},
)
