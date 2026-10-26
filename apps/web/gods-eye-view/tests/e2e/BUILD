# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

package(default_visibility = ["//visibility:public"])

exports_files(glob(["src/**/*.rs"]))

sh_binary(
    name = "runner",
    srcs = ["run-e2e-tests.sh"],
    data = [
        ":tier1_feature_test.sh",
        ":tier2_boundary_test.sh",
        ":tier3_combination_test.sh",
        ":tier4_scenario_test.sh",
        ":tier5_adversarial_test.sh",
    ],
)

sh_test(
    name = "tier1_feature_test",
    size = "medium",
    srcs = ["tier1_feature_test.sh"],
    tags = [
        "local",
        "manual",
    ],
)

sh_test(
    name = "tier2_boundary_test",
    size = "medium",
    srcs = ["tier2_boundary_test.sh"],
    tags = [
        "local",
        "manual",
    ],
)

sh_test(
    name = "tier3_combination_test",
    size = "medium",
    srcs = ["tier3_combination_test.sh"],
    tags = [
        "local",
        "manual",
    ],
)

sh_test(
    name = "tier4_scenario_test",
    size = "medium",
    srcs = ["tier4_scenario_test.sh"],
    tags = [
        "local",
        "manual",
    ],
)

sh_test(
    name = "tier5_adversarial_test",
    size = "medium",
    srcs = ["tier5_adversarial_test.sh"],
    tags = [
        "local",
        "manual",
    ],
)

sh_test(
    name = "run_e2e_tests",
    size = "large",
    srcs = ["run-e2e-tests.sh"],
    data = [
        ":tier1_feature_test.sh",
        ":tier2_boundary_test.sh",
        ":tier3_combination_test.sh",
        ":tier4_scenario_test.sh",
        ":tier5_adversarial_test.sh",
    ],
    tags = [
        "local",
        "manual",
    ],
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
