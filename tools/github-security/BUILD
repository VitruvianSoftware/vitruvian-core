# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""GitHub repository security settings that repo-config/Pulumi cannot express.

`infrastructure/pulumi/platform/repo-config` is the authority for repo governance
and owns everything it CAN own (secret scanning, push protection, Dependabot
security updates, the merge-queue ruleset). This package exists only for the
narrow set the pinned provider cannot reach.

  bazel run //tools/github-security:enable-dependency-graph   # prerequisite for dependency-review

Dependency graph is the worked example: pulumi-github v6.14.0 exposes it on the
ORGANIZATION resource only, never per repository, and
PATCH /repos/{owner}/{repo} silently ignores a
security_and_analysis[dependency_graph] field. The only working path is an
org-level code security configuration attached to the repo — which the target
does surgically, leaving every other setting `not_set` so it can never fight
Pulumi. The target is idempotent and prompts for the admin:org scope it needs
rather than telling the operator to go and get it.
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "github_security_lib",
    srcs = ["src/lib.rs"],
    crate_name = "github_security",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_binary(
    name = "enable-dependency-graph",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":github_security_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

rust_test(
    name = "github_security_lib_test",
    size = "small",
    crate = ":github_security_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "enable-dependency-graph_test",
    tests = [":github_security_lib_test"],
)

test_suite(
    name = "enable_test",
    tests = [":github_security_lib_test"],
)
