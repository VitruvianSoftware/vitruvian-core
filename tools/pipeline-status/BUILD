# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

"""Determines the complete health status of all workflows triggered on main.

  bazel run //tools/pipeline-status -- [commit-sha|pr-number]

Exit codes:
  0: All post-merge workflows on main passed (GREEN).
  1: One or more workflows failed (RED).
  2: Workflows are currently in-flight (PENDING / IN_PROGRESS).
  3: No workflow runs found, or the target could not be resolved.
"""

# Hand-written: gazelle would otherwise generate targets beside these.
# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "pipeline_status_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = [
            "src/main.rs",
            "src/probe.rs",
            "src/bin/mouse_daemon.rs",
        ],
    ),
    crate_name = "pipeline_status",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "pipeline-status",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":pipeline_status_lib"],
)

# `manual` because data includes the macOS-only gravastar-mouse binary.
rust_binary(
    name = "pipeline-mouse-daemon",
    srcs = ["src/bin/mouse_daemon.rs"],
    data = ["//packages/peripherals:gravastar-mouse"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = ["manual"],
    visibility = ["//visibility:public"],
    deps = [":pipeline_status_lib"],
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "pipeline_status_lib_test",
    size = "small",
    crate = ":pipeline_status_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "pipeline-status_test",
    tests = [":pipeline_status_lib_test"],
)

test_suite(
    name = "pipeline-mouse-daemon_test",
    tests = [":pipeline_status_lib_test"],
)
