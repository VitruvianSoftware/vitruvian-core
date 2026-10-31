# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# Asks the REGISTRY whether our published packages are actually there, rather
# than asking the pipeline whether it thinks it published them. Those stopped
# being the same thing on 2026-05-07 and nothing noticed for three months.
rust_library(
    name = "npm_publish_audit_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "npm_publish_audit",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "check",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":npm_publish_audit_lib"],
)

rust_test(
    name = "npm_publish_audit_lib_test",
    size = "small",
    crate = ":npm_publish_audit_lib",
    edition = "2021",
)

test_suite(
    name = "check_test",
    tests = [":npm_publish_audit_lib_test"],
)

test_suite(
    name = "audit_test",
    tests = [":npm_publish_audit_lib_test"],
)
