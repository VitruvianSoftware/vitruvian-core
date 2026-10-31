# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Store or rotate a GitHub App's private key as a repo secret.

  bazel run //tools/github-app-key -- renovate        # finds the .pem in ~/Downloads
  bazel run //tools/github-app-key -- --list          # which Apps it knows

GitHub cannot automate "Generate a private key" in the App's settings. This
does everything after it: proves the key belongs to the right App (by signing
an App JWT and asking GitHub), checks the App is installed and -- where it must
be -- NOT a merge-queue bypass actor, stores it with `gh secret set` over stdin
(never printed), then offers to delete the download.
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "github_app_key_lib",
    srcs = ["src/lib.rs"],
    crate_name = "github_app_key",
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
    name = "github-app-key",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":github_app_key_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

rust_test(
    name = "github_app_key_lib_test",
    size = "small",
    crate = ":github_app_key_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "set-key_test",
    tests = [":github_app_key_lib_test"],
)

test_suite(
    name = "rotate_test",
    tests = [":github_app_key_lib_test"],
)
