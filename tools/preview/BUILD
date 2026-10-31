# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Ephemeral PR preview tooling: Neon database branches, the preview deploy,
and the sticky PR comment.

  bazel run //tools/preview:neon-branch -- create --project-id <p> --branch-name <b>
  bazel run //tools/preview:provision-preview -- --app <app> --pr <n> --dry-run
  bazel run //tools/preview:pr-comment -- --pr <n> --app <app> --status ready --dry-run
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

package(default_visibility = ["//visibility:public"])

# The three tools' logic, and the slice of jq they need, over serde_json.
rust_library(
    name = "preview_lib",
    srcs = [
        "src/common.rs",
        "src/jq.rs",
        "src/lib.rs",
        "src/neon_branch.rs",
        "src/pr_comment.rs",
        "src/provision_preview.rs",
    ],
    crate_name = "preview",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "neon-branch",
    srcs = ["src/bin/neon_branch.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        ":preview_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "provision-preview",
    srcs = ["src/bin/provision_preview.rs"],
    data = [
        ":neon-branch",
        ":pr-comment",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        ":preview_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "pr-comment",
    srcs = ["src/bin/pr_comment.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        ":preview_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

rust_test(
    name = "preview_lib_test",
    size = "small",
    crate = ":preview_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "neon-branch_test",
    tests = [":preview_lib_test"],
)

test_suite(
    name = "provision-preview_test",
    tests = [":preview_lib_test"],
)

test_suite(
    name = "pr-comment_test",
    tests = [":preview_lib_test"],
)
