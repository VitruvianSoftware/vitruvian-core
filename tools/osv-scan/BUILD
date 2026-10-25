# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Scan this repo's lockfiles for known advisories (OSV database).

  bazel run //tools/osv-scan

Replaces GitHub's `dependency-review`, which reads GitHub's dependency graph --
an Advanced Security feature that is free on public repos but billed per active
committer on private ones, and (verified against the API) cannot be enabled
without `advanced_security`. osv-scanner reads the lockfiles directly, so it
costs nothing at any visibility, runs locally as well as in CI, and also covers
Cargo and PyPI. See tools/osv-scan/osv-scan.sh for the full rationale.
"""

# Hand-written: gazelle has no Rust extension here, and the shell fallback and
# parity tests below are not something it would generate.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["osv-scan.sh"])

# src/ is osv-scan.sh in Rust: same scan, retries, fallback, coverage and
# read-only assertions, diff-scoped verdict, messages and exit codes, byte for
# byte (see :osv_scan_rs_parity_test). What the script did with jq, python3 and
# coreutils is done in-process (JSON through serde_json); git, tar and
# osv-scanner are still the real programs. src/lib.rs lists the divergences.
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
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
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

# The original script, kept runnable as a fallback and as the parity oracle.
sh_binary(
    name = "osv-scan-sh",
    srcs = ["osv-scan.sh"],
    visibility = ["//visibility:public"],
)

rust_test(
    name = "osv_scan_lib_test",
    size = "small",
    crate = ":osv_scan_lib",
    edition = "2021",
)

sh_test(
    name = "osv-scan_test",
    size = "small",
    srcs = ["osv-scan_test.sh"],
    data = ["osv-scan.sh"],
)

# osv-scan_test.sh runs its target with `bash`, so hand it a one-line script
# that execs the Rust binary sitting beside it in the runfiles tree.
genrule(
    name = "osv_scan_rs_shim",
    outs = ["osv_scan_rs_shim.sh"],
    cmd = "printf '%s\\n' '#!/usr/bin/env bash' " +
          "'exec \"$$(cd \"$$(dirname \"$${BASH_SOURCE[0]}\")\" && pwd)/osv-scan\" \"$$@\"' > $@",
)

# The same suite, against the Rust binary. Its three "the read-only flags are
# passed" greps read the Rust source that passes them instead of the shim.
sh_test(
    name = "osv-scan-rs_test",
    size = "small",
    srcs = ["osv-scan_test.sh"],
    data = [
        "src/scan.rs",
        ":osv-scan",
        ":osv_scan_rs_shim",
    ],
    env = {
        "OSV_SCAN_IMPL_SRC": "$(rootpath src/scan.rs)",
        "OSV_SCAN_UNDER_TEST": "$(rootpath :osv_scan_rs_shim)",
    },
)

# osv-scan.sh and the Rust binary side by side over every scenario in
# osv-scan_test.sh plus the edge cases (retry budgets and delays, transient vs
# deterministic failures, the --no-resolve fallback, BASE_REV / BASE_REF,
# version-only manifest bumps, malformed or odd JSON, the MIN_SOURCES
# boundary, tree mutation on every path, GitHub annotations): stdout, stderr,
# exit code, the scanner's argv and the tree left behind must all be identical.
py_test(
    name = "osv_scan_rs_parity_test",
    size = "medium",
    srcs = ["osv_scan_rs_parity_test.py"],
    data = [
        "osv-scan.sh",
        ":osv-scan",
    ],
    env = {
        "OSV_SCAN_RS": "$(rootpath :osv-scan)",
        "OSV_SCAN_SH": "$(rootpath osv-scan.sh)",
    },
    main = "osv_scan_rs_parity_test.py",
)
