# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""How main's merge queue did over a window: speed, ejections, breakage.

  bazel run //tools/merge-queue-stats -- --since 2026-10-05 --until 2026-10-19

Written to judge the switch to HEADGREEN grouping: run it on the window
before a queue change and the window after, and compare.
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "merge_queue_stats_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "merge_queue_stats",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "merge-queue-stats",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":merge_queue_stats_lib"],
)

alias(
    name = "merge-queue-stats-rs",
    actual = ":merge-queue-stats",
)

alias(
    name = "merge_queue_stats_rs",
    actual = ":merge-queue-stats",
)

rust_test(
    name = "merge_queue_stats_lib_test",
    size = "small",
    crate = ":merge_queue_stats_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "merge_queue_stats_test",
    tests = [":merge_queue_stats_lib_test"],
)

test_suite(
    name = "merge-queue-stats_test",
    tests = [":merge_queue_stats_lib_test"],
)
