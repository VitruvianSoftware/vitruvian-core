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

# Hand-written: the Rust port and its Python parity test would otherwise get
# gazelle-generated targets beside these.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["pipeline-status.sh"])

# --- The Rust port (the default) ---------------------------------------------
# src/ is pipeline-status.sh in Rust: same arguments, environment, gh and git
# calls, output and exit codes. It reads JSON with serde_json and evaluates
# the runs the way the script's jq branch does, so it needs neither jq nor
# python3. Optimised in every build mode.
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

# Test-only: answers for `evaluate_runs_json`, which the shell test sources
# from the script, so the same test can run against the binary.
rust_binary(
    name = "pipeline-status-rs-probe",
    testonly = True,
    srcs = ["src/probe.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":pipeline_status_lib"],
)

# The script, kept runnable beside the port.
sh_binary(
    name = "pipeline-status-sh",
    srcs = ["pipeline-status.sh"],
    visibility = ["//visibility:public"],
)

# --- The Rust port of pipeline-mouse-daemon --------------------------------
# Same LED state matrix, signal handling and output as the shell script.
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

# Test-only binary without the macOS-only data dep (GRAVASTAR_BIN is
# stubbed by the test, so the real binary is never needed at build time).
rust_binary(
    name = "pipeline-mouse-daemon-test-bin",
    testonly = True,
    srcs = ["src/bin/mouse_daemon.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":pipeline_status_lib"],
)

# The shell script, kept runnable beside the Rust port.
sh_binary(
    name = "pipeline-mouse-daemon-sh",
    srcs = ["pipeline-mouse-daemon.sh"],
    data = [
        "pipeline-status.sh",
        "//packages/peripherals:gravastar-mouse",
    ],
    tags = ["manual"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "pipeline-mouse-daemon_test",
    size = "small",
    srcs = ["pipeline-mouse-daemon_test.sh"],
    args = ["$(rootpath :pipeline-mouse-daemon-test-bin)"],
    data = [":pipeline-mouse-daemon-test-bin"],
)

sh_test(
    name = "pipeline-status_test",
    size = "small",
    srcs = ["pipeline-status_test.sh"],
    args = ["$(location pipeline-status.sh)"],
    data = ["pipeline-status.sh"],
)

# The same shell test against the Rust binary.
sh_test(
    name = "pipeline-status-rs_test",
    size = "small",
    srcs = ["pipeline-status_test.sh"],
    args = [
        "$(rootpath :pipeline-status)",
        "$(rootpath :pipeline-status-rs-probe)",
    ],
    data = [
        ":pipeline-status",
        ":pipeline-status-rs-probe",
    ],
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "pipeline_status_lib_test",
    size = "small",
    crate = ":pipeline_status_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# pipeline-status.sh and the Rust binary side by side: a few thousand runs
# answers (GitHub's real shapes, then generated and mutated ones) through
# `evaluate_runs_json` and through both programs end to end against a mock gh
# and scratch git repositories, with the script's jq branch (the pinned
# hermetic jq) and its python3 branch. Exit codes, stdout, stderr and the gh
# and git calls must match.
py_test(
    name = "pipeline_status_rs_parity_test",
    size = "medium",
    srcs = ["pipeline_status_rs_parity_test.py"],
    data = [
        "pipeline-status.sh",
        ":pipeline-status",
        ":pipeline-status-rs-probe",
        "@jq_toolchains//:resolved_toolchain",
    ],
    env = {
        "JQ_BIN": "$(JQ_BIN)",
        "PIPELINE_STATUS_RS": "$(rootpath :pipeline-status)",
        "PIPELINE_STATUS_RS_PROBE": "$(rootpath :pipeline-status-rs-probe)",
        "PIPELINE_STATUS_SH": "$(rootpath pipeline-status.sh)",
    },
    main = "pipeline_status_rs_parity_test.py",
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
)
