# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

package(default_visibility = ["//visibility:public"])

exports_files(glob(["src/**/*.rs"]))

alias(
    name = "runner",
    actual = ":run_e2e_tests_rs",
)

test_suite(
    name = "tier1_feature_test",
    tags = ["local"],
    tests = [":tier1_feature_rs_test"],
)

test_suite(
    name = "tier2_boundary_test",
    tags = ["local"],
    tests = [":tier2_boundary_rs_test"],
)

test_suite(
    name = "tier3_combination_test",
    tags = ["local"],
    tests = [":tier3_combination_rs_test"],
)

test_suite(
    name = "tier4_scenario_test",
    tags = ["local"],
    tests = [":tier4_scenario_rs_test"],
)

test_suite(
    name = "tier5_adversarial_test",
    tags = ["local"],
    tests = [":tier5_adversarial_rs_test"],
)

test_suite(
    name = "run_e2e_tests",
    tags = ["local"],
    tests = [":e2e_rs_test"],
)

rust_library(
    name = "e2e_rs_lib",
    srcs = glob(["src/*.rs"]),
    crate_name = "gods_eye_view_e2e",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "run_e2e_tests_rs",
    srcs = ["src/bin/run_e2e_tests.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":e2e_rs_lib"],
)

rust_binary(
    name = "tier1_feature_test_rs",
    srcs = ["src/bin/tier1_feature_test.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":e2e_rs_lib"],
)

rust_binary(
    name = "tier2_boundary_test_rs",
    srcs = ["src/bin/tier2_boundary_test.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":e2e_rs_lib"],
)

rust_binary(
    name = "tier3_combination_test_rs",
    srcs = ["src/bin/tier3_combination_test.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":e2e_rs_lib"],
)

rust_binary(
    name = "tier4_scenario_test_rs",
    srcs = ["src/bin/tier4_scenario_test.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":e2e_rs_lib"],
)

rust_binary(
    name = "tier5_adversarial_test_rs",
    srcs = ["src/bin/tier5_adversarial_test.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":e2e_rs_lib"],
)

rust_test(
    name = "e2e_rs_test",
    size = "small",
    crate = ":e2e_rs_lib",
    data = ["//apps/web/gods-eye-view:BUILD.bazel"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = ["local"],
)

rust_test(
    name = "tier1_feature_rs_test",
    size = "small",
    srcs = ["src/bin/tier1_feature_test.rs"],
    data = ["//apps/web/gods-eye-view:BUILD.bazel"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = ["local"],
    deps = [":e2e_rs_lib"],
)

rust_test(
    name = "tier2_boundary_rs_test",
    size = "small",
    srcs = ["src/bin/tier2_boundary_test.rs"],
    data = ["//apps/web/gods-eye-view:BUILD.bazel"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = ["local"],
    deps = [":e2e_rs_lib"],
)

rust_test(
    name = "tier3_combination_rs_test",
    size = "small",
    srcs = ["src/bin/tier3_combination_test.rs"],
    data = ["//apps/web/gods-eye-view:BUILD.bazel"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = ["local"],
    deps = [":e2e_rs_lib"],
)

rust_test(
    name = "tier4_scenario_rs_test",
    size = "small",
    srcs = ["src/bin/tier4_scenario_test.rs"],
    data = ["//apps/web/gods-eye-view:BUILD.bazel"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = ["local"],
    deps = [":e2e_rs_lib"],
)

rust_test(
    name = "tier5_adversarial_rs_test",
    size = "small",
    srcs = ["src/bin/tier5_adversarial_test.rs"],
    data = ["//apps/web/gods-eye-view:BUILD.bazel"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = ["local"],
    deps = [":e2e_rs_lib"],
)
