# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "parity_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "parity_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "parity",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":parity_lib"],
)

alias(
    name = "parity-rs",
    actual = ":parity",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "parity_lib_test",
    size = "small",
    crate = ":parity_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "parity_test",
    tests = [":parity_lib_test"],
)
