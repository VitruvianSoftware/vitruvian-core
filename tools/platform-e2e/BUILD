# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

# Hand-written: the Rust and Python targets below are not gazelle's to own.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

package(default_visibility = ["//visibility:public"])

exports_files(["runner.sh"])

_RUNNER_DATA = [
    ":tier1_feature_test.sh",
    ":tier2_boundary_test.sh",
    ":tier3_combination_test.sh",
    ":tier4_workload_test.sh",
    "//tools/owners",
    "//tools/pipeline/gen",
    "//tools/pipeline/plan",
]

# `:runner` is the Rust port (src/): runner.sh's options, report formats and
# exit codes, held to the script by runner_rs_parity_test. The script stays
# as `:runner-sh`, and `:runner_test` still runs it.
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

alias(
    name = "runner-rs",
    actual = ":runner",
)

alias(
    name = "runner_rs",
    actual = ":runner",
)

sh_binary(
    name = "runner-sh",
    srcs = ["runner.sh"],
    data = _RUNNER_DATA,
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "runner_lib_test",
    size = "small",
    crate = ":runner_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Script and binary side by side, each beside the same fake tier scripts:
# exit code, stdout and stderr compared byte for byte (durations aside).
py_test(
    name = "runner_rs_parity_test",
    size = "medium",
    srcs = ["runner_rs_parity_test.py"],
    data = [
        "runner.sh",
        ":runner",
    ],
    env = {
        "RUNNER_RS": "$(rootpath :runner)",
        "RUNNER_SH": "$(rootpath runner.sh)",
    },
    main = "runner_rs_parity_test.py",
    deps = ["//tools/shell-compat:parity_harness"],
)

sh_test(
    name = "tier1_feature_test",
    size = "medium",
    srcs = ["tier1_feature_test.sh"],
    data = [
        "//tools/boundaries:package_groups.bzl",
        "//tools/lint:boundaries.bzl",
        "//tools/owners",
        "//tools/pipeline/gen",
        "//tools/pipeline/plan",
    ],
    tags = ["manual"],
)

sh_test(
    name = "tier2_boundary_test",
    size = "medium",
    srcs = ["tier2_boundary_test.sh"],
    data = [
        "//tools/boundaries:package_groups.bzl",
        "//tools/lint:boundaries.bzl",
        "//tools/owners",
        "//tools/pipeline/gen",
        "//tools/pipeline/plan",
    ],
    tags = ["manual"],
)

sh_test(
    name = "tier3_combination_test",
    size = "medium",
    srcs = ["tier3_combination_test.sh"],
    data = [
        "//tools/owners",
        "//tools/pipeline/gen",
        "//tools/pipeline/plan",
    ],
    tags = ["manual"],
)

sh_test(
    name = "tier4_workload_test",
    size = "medium",
    srcs = ["tier4_workload_test.sh"],
    data = [
        "//tools/boundaries:package_groups.bzl",
        "//tools/lint:boundaries.bzl",
        "//tools/owners",
        "//tools/pipeline/gen",
        "//tools/pipeline/plan",
    ],
    tags = ["manual"],
)

sh_test(
    name = "runner_test",
    size = "large",
    srcs = ["runner.sh"],
    data = [
        ":tier1_feature_test.sh",
        ":tier2_boundary_test.sh",
        ":tier3_combination_test.sh",
        ":tier4_workload_test.sh",
        "//tools/owners",
        "//tools/pipeline/gen",
        "//tools/pipeline/plan",
    ],
    tags = ["manual"],
)
