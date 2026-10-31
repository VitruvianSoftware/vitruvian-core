# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

package(default_visibility = ["//visibility:public"])

_RUNNER_DATA = [
    "//tools/owners",
    "//tools/pipeline/gen",
    "//tools/pipeline/plan",
]

rust_library(
    name = "runner_lib",
    srcs = ["src/lib.rs"],
    crate_name = "runner",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "runner",
    srcs = ["src/main.rs"],
    data = _RUNNER_DATA,
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":runner_lib"],
)

rust_test(
    name = "runner_lib_test",
    size = "small",
    crate = ":runner_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "tier1_feature_test",
    tests = [":runner_lib_test"],
)

test_suite(
    name = "tier2_boundary_test",
    tests = [":runner_lib_test"],
)

test_suite(
    name = "tier3_combination_test",
    tests = [":runner_lib_test"],
)

test_suite(
    name = "tier4_workload_test",
    tests = [":runner_lib_test"],
)

test_suite(
    name = "runner_test",
    tests = [":runner_lib_test"],
)
