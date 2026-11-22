# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""JSON as a Python script's `print(json.load(...)[...])` shows it, for the Rust ports of bash tools that read JSON with python3."""

load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")

rust_library(
    name = "vitruvian_pyjson",
    srcs = ["src/lib.rs"],
    crate_name = "vitruvian_pyjson",
    edition = "2021",
    visibility = ["//visibility:public"],
    deps = [
        "//packages/pycompat/vitruvian-pycompat:vitruvian_pycompat",
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_test(
    name = "vitruvian_pyjson_test",
    size = "small",
    crate = ":vitruvian_pyjson",
)
