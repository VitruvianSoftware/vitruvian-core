# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Scan this repo's lockfiles for known advisories (OSV database).

  bazel run //tools/osv-scan

Replaces GitHub's `dependency-review`, which reads GitHub's dependency graph --
an Advanced Security feature that is free on public repos but billed per active
committer on private ones, and (verified against the API) cannot be enabled
without `advanced_security`. osv-scanner reads the lockfiles directly, so it
costs nothing at any visibility, runs locally as well as in CI, and also covers
Cargo and PyPI.
"""

# Hand-written: gazelle has no Rust extension here.
# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "osv_scan_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "osv_scan",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "osv-scan",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":osv_scan_lib"],
)

alias(
    name = "osv-scan-rs",
    actual = ":osv-scan",
    visibility = ["//visibility:public"],
)

alias(
    name = "osv_scan_rs",
    actual = ":osv-scan",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "osv_scan_lib_test",
    size = "small",
    crate = ":osv_scan_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "osv-scan_test",
    tests = [":osv_scan_lib_test"],
)

test_suite(
    name = "osv-scan-rs_test",
    tests = [":osv_scan_lib_test"],
)
