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

# Hand-written: the Rust port and its Python files would otherwise get
# gazelle-generated targets beside these.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["watch-pr.sh"])

# --- The Rust port (the default) ---------------------------------------------
# src/ is watch-pr.sh in Rust: same arguments, environment, gh, git and bazel
# calls, output and exit codes. Checks JSON is read with serde_json and
# classified the way the script's python3 branch does it; src/pyprint.rs
# (from gen_unicode_tables.py) is what Python counts as printable when it
# prints a value. Optimised in every build mode.
rust_library(
    name = "watch_pr_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = [
            "src/main.rs",
            "src/probe.rs",
        ],
    ),
    # The usage test holds the help text to the script's.
    compile_data = ["watch-pr.sh"],
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

# Test-only: answers for `parse_checks_json`, which the shell test sources
# from the script, so the same test can run against the binary.
rust_binary(
    name = "watch-pr-rs-probe",
    testonly = True,
    srcs = ["src/probe.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":watch_pr_lib"],
)

# The script, kept runnable beside the port.
sh_binary(
    name = "watch-pr-sh",
    srcs = ["watch-pr.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "watch-pr_test",
    size = "small",
    srcs = ["watch-pr_test.sh"],
    data = ["watch-pr.sh"],
)

# The same shell test against the Rust binary.
sh_test(
    name = "watch-pr-rs_test",
    size = "small",
    srcs = ["watch-pr_test.sh"],
    args = [
        "$(rootpath :watch-pr)",
        "$(rootpath :watch-pr-rs-probe)",
    ],
    data = [
        ":watch-pr",
        ":watch-pr-rs-probe",
    ],
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "watch_pr_lib_test",
    size = "small",
    crate = ":watch_pr_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# watch-pr.sh and the Rust binary side by side: `parse_checks_json` over a
# few thousand checks answers, then both programs end to end through every
# phase (checks, merge queue, post-merge, timeouts, argument errors) against
# a mock gh and bazel and scratch git repositories, with the real
# pipeline-status.sh as well as scripted ones. Exit codes, stdout, stderr and
# the gh and bazel calls must match once the clock is masked.
py_test(
    name = "watch_pr_rs_parity_test",
    size = "large",
    srcs = ["watch_pr_rs_parity_test.py"],
    data = [
        "gen_unicode_tables.py",
        "src/pyprint.rs",
        "watch-pr.sh",
        ":watch-pr",
        ":watch-pr-rs-probe",
        "//tools/pipeline-status:pipeline-status.sh",
    ],
    env = {
        "PIPELINE_STATUS_SH": "$(rootpath //tools/pipeline-status:pipeline-status.sh)",
        "WATCH_PR_RS": "$(rootpath :watch-pr)",
        "WATCH_PR_RS_PROBE": "$(rootpath :watch-pr-rs-probe)",
        "WATCH_PR_SH": "$(rootpath watch-pr.sh)",
    },
    main = "watch_pr_rs_parity_test.py",
)
