# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

"""Checks across the Antigravity plugins under plugins/."""

load("@rules_rust//rust:defs.bzl", "rust_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

PLUGINS = [
    "ext-marketplace",
    "gh-watch",
    "hookify",
    "live-context",
    "ralph-loop",
    "receipts-report",
    "savvy-fleet",
    "security-guidance",
    "worktree-band",
]

CONFORMANCE = ["//apps/desktop/antigravity/plugins/%s:conformance_files" % p for p in PLUGINS]

# The files the tests read reach them in $CONFORMANCE_FILES, not as
# arguments: libtest would take arguments as test-name filters.
CONFORMANCE_ENV = {
    "CONFORMANCE_FILES": " ".join(["$(rootpaths %s)" % c for c in CONFORMANCE]),
}

# Every hooks.json has the shape Antigravity loads (a wrong entry gets the
# whole file skipped), and no PreToolUse hook can fall back to `{}`, which
# Antigravity treats as a denial.
rust_test(
    name = "hooks_json_test",
    size = "small",
    srcs = ["hooks_json_test.rs"],
    crate_root = "hooks_json_test.rs",
    data = CONFORMANCE,
    edition = "2021",
    env = CONFORMANCE_ENV,
    deps = ["@crates//:serde_json"],
)

# The files every plugin carries its own copy of are identical.
rust_test(
    name = "shared_files_test",
    size = "small",
    srcs = ["shared_files_test.rs"],
    crate_root = "shared_files_test.rs",
    data = CONFORMANCE,
    edition = "2021",
    env = CONFORMANCE_ENV,
)

# Run on every PR that touches a plugin, not only in the nightly full sweep.
pipeline_unit(
    name = "antigravity-plugins-conformance",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":hooks_json_test",
        ":shared_files_test",
    ],
    tier = "L1",
    timeout_minutes = 15,
)
