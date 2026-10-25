# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Ephemeral PR preview tooling: Neon database branches, the preview deploy,
and the sticky PR comment.

  bazel run //tools/preview:neon-branch -- create --project-id <p> --branch-name <b>
  bazel run //tools/preview:provision-preview -- --app <app> --pr <n> --dry-run
  bazel run //tools/preview:pr-comment -- --pr <n> --app <app> --status ready --dry-run

Each tool is Rust (src/; one library, a thin src/bin/ entry point per tool),
held byte for byte to the bash script it was ported from by the parity test
below. The scripts stay runnable as :<tool>-sh and stay exported for anyone
who calls them by path.
"""

# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

package(default_visibility = ["//visibility:public"])

exports_files([
    "provision-preview.sh",
    "neon-branch.sh",
    "pr-comment.sh",
])

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

# Runs the neon-branch next to it (in data), as the script runs
# neon-branch.sh from its own directory.
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

[
    alias(
        name = name,
        actual = ":" + tool,
    )
    for tool in [
        "neon-branch",
        "pr-comment",
        "provision-preview",
    ]
    for name in [
        tool + "-rs",
        tool.replace("-", "_") + "_rs",
    ]
]

# The shell originals, kept runnable and held to the ports by the parity test.
sh_binary(
    name = "neon-branch-sh",
    srcs = ["neon-branch.sh"],
)

sh_binary(
    name = "provision-preview-sh",
    srcs = ["provision-preview.sh"],
    data = [
        ":neon-branch.sh",
        ":neon-branch-sh",
        ":pr-comment-sh",
    ],
)

sh_binary(
    name = "pr-comment-sh",
    srcs = ["pr-comment.sh"],
)

sh_test(
    name = "neon-branch_test",
    size = "small",
    srcs = ["neon-branch_test.sh"],
    args = ["$(location :neon-branch.sh)"],
    data = [":neon-branch.sh"],
)

# The same suite against the Rust binary (NEON_BRANCH_BIN).
sh_test(
    name = "neon-branch-rs_test",
    size = "small",
    srcs = ["neon-branch_test.sh"],
    args = ["$(location :neon-branch.sh)"],
    data = [
        ":neon-branch",
        ":neon-branch.sh",
    ],
    env = {"NEON_BRANCH_BIN": "$(rootpath :neon-branch)"},
)

sh_test(
    name = "provision-preview_test",
    size = "small",
    srcs = ["provision-preview_test.sh"],
    args = ["$(location :provision-preview.sh)"],
    data = [
        ":neon-branch.sh",
        ":pr-comment.sh",
        ":provision-preview.sh",
    ],
)

sh_test(
    name = "provision-preview-rs_test",
    size = "small",
    srcs = ["provision-preview_test.sh"],
    args = ["$(location :provision-preview.sh)"],
    data = [
        ":provision-preview",
        ":provision-preview.sh",
    ],
    env = {"PROVISION_PREVIEW_BIN": "$(rootpath :provision-preview)"},
)

sh_test(
    name = "pr-comment_test",
    size = "small",
    srcs = ["pr-comment_test.sh"],
    args = ["$(location :pr-comment.sh)"],
    data = [":pr-comment.sh"],
)

sh_test(
    name = "pr-comment-rs_test",
    size = "small",
    srcs = ["pr-comment_test.sh"],
    args = ["$(location :pr-comment.sh)"],
    data = [
        ":pr-comment",
        ":pr-comment.sh",
    ],
    env = {"PR_COMMENT_BIN": "$(rootpath :pr-comment)"},
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "preview_lib_test",
    size = "small",
    crate = ":preview_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Script and binary side by side on every case in preview_rs_parity_test.py,
# for all three tools: exit code, stdout, stderr, and every call made to the
# fake curl, gcloud, kubectl and gh (argv and stdin), compared byte for byte.
# The scripts' jq is the hermetic one.
py_test(
    name = "preview_rs_parity_test",
    size = "medium",
    srcs = ["preview_rs_parity_test.py"],
    data = [
        ":neon-branch",
        ":neon-branch.sh",
        ":pr-comment",
        ":pr-comment.sh",
        ":provision-preview",
        ":provision-preview.sh",
        "@jq_toolchains//:resolved_toolchain",
    ],
    env = {
        "JQ_BIN": "$(JQ_BIN)",
        "NEON_BRANCH_RS": "$(rootpath :neon-branch)",
        "NEON_BRANCH_SH": "$(rootpath :neon-branch.sh)",
        "PR_COMMENT_RS": "$(rootpath :pr-comment)",
        "PR_COMMENT_SH": "$(rootpath :pr-comment.sh)",
        "PROVISION_PREVIEW_RS": "$(rootpath :provision-preview)",
        "PROVISION_PREVIEW_SH": "$(rootpath :provision-preview.sh)",
    },
    main = "preview_rs_parity_test.py",
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
    deps = ["//tools/shell-compat:parity_harness"],
)
