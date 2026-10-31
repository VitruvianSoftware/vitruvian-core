# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "scripts_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/bin/*.rs"],
    ),
    crate_name = "scripts_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "kind-cluster",
    srcs = ["src/bin/kind_cluster.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":scripts_lib"],
)

rust_binary(
    name = "agy-bin",
    srcs = ["src/bin/agy.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":scripts_lib"],
)

alias(
    name = "agy",
    actual = ":agy-bin",
    visibility = ["//visibility:public"],
)

rust_binary(
    name = "copilot-bin",
    srcs = ["src/bin/copilot.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":scripts_lib"],
)

alias(
    name = "copilot",
    actual = ":copilot-bin",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "scripts_lib_test",
    size = "small",
    crate = ":scripts_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "verify-gcp-setup_test",
    tests = [":scripts_lib_test"],
)
