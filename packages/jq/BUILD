# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""jq 1.8 compatibility primitives for Rust ports of jq-using scripts.

No third-party crates, so plain-rustc CI tools can link it via rustc-build.sh.
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")

rust_library(
    name = "vitruvian_jq",
    srcs = glob(["src/**/*.rs"]),
    crate_name = "vitruvian_jq",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
)

rust_test(
    name = "vitruvian_jq_test",
    size = "small",
    crate = ":vitruvian_jq",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_test(
    name = "parity_test",
    size = "small",
    srcs = ["tests/parity_test.rs"],
    data = ["tests/parity_cases.tsv"],
    edition = "2021",
    env = {"PARITY_CASES": "$(rootpath tests/parity_cases.tsv)"},
    rustc_flags = ["-Copt-level=3"],
    deps = [":vitruvian_jq"],
)

filegroup(
    name = "srcs",
    srcs = glob(["src/**/*.rs"]),
    visibility = [
        "//packages/pycompat/vitruvian-pycompat:__pkg__",
        "//tools/ci:__pkg__",
    ],
)
