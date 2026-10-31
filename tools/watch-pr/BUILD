# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

"""Autonomous, robust PR check monitoring, merge queue, and post-merge pipeline verification.

  bazel run //tools/watch-pr -- <pr-number|branch|sha> [options]

Exit codes:
  0: Success (all checks passed, landed on main, post-merge pipeline green).
  1: Check or workflow failure (diagnostic logs printed).
  2: Timeout reached.
  3: Invalid argument or configuration error.
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "watch_pr_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = [
            "src/main.rs",
            "src/probe.rs",
        ],
    ),
    crate_name = "watch_pr",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "watch-pr",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":watch_pr_lib"],
)

rust_binary(
    name = "watch-pr-probe",
    testonly = True,
    srcs = ["src/probe.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":watch_pr_lib"],
)

rust_test(
    name = "watch_pr_lib_test",
    size = "small",
    crate = ":watch_pr_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "watch-pr_test",
    tests = [":watch_pr_lib_test"],
)
