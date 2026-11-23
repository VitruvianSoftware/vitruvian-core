# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

"""Checks across the Antigravity plugins under plugins/."""

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
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

# Plugins under plugins/ that have their own BUILD file but no hooks/ directory.
NO_HOOK_PLUGINS = [
    "vitruvian-orchestrator",
]

# Generated hook files inside any new plugin folder that does not yet have its
# own BUILD file (Bazel's glob() stops at subpackage boundaries, so this reaches
# folders without a BUILD file).
UNLISTED_HOOK_FILES = glob(
    [
        "plugins/*/hooks/rust-hook.sh",
        "plugins/*/hooks/rust-hook_test.sh",
        "plugins/*/hooks/src/json.rs",
    ],
    allow_empty = True,
)

# Direct plugin subpackages (folders with their own BUILD file). Bazel's glob()
# cannot descend into subpackages, so subpackages() ensures a new plugin with a
# BUILD file cannot silently bypass hooks_drift_test either.
PLUGIN_SUBPACKAGES = [
    p[len("plugins/"):]
    for p in subpackages(include = ["plugins/*"])
]

exports_files(
    ["plugins/README.md"],
    visibility = ["//apps/antigravity/plugins/ext-marketplace:__pkg__"],
)

CONFORMANCE = ["//apps/antigravity/plugins/%s:conformance_files" % p for p in PLUGINS]

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

# The version-consistency test every plugin runs as :version_rs_test.
exports_files(
    ["plugin_version_test.rs"],
    visibility = ["//apps/antigravity/plugins:__subpackages__"],
)

# Canonical hook sources and generator/drift check across Antigravity plugins.
rust_test(
    name = "hook_json_helper_test",
    size = "small",
    srcs = ["hook_json_helper.rs"],
    crate_root = "hook_json_helper.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_library(
    name = "hooks_gen_lib",
    srcs = ["hooks_gen_lib.rs"],
    crate_name = "hooks_gen",
    crate_root = "hooks_gen_lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "hooks-gen",
    srcs = ["hooks_gen.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":hooks_gen_lib"],
)

rust_test(
    name = "hooks_drift_test",
    size = "small",
    crate = ":hooks_gen_lib",
    data = [
        "hook_json_helper.rs",
        "hook_rust_hook.sh",
        "hook_rust_hook_test.sh",
    ] + CONFORMANCE + UNLISTED_HOOK_FILES,
    edition = "2021",
    env = dict(
        CONFORMANCE_ENV,
        NO_HOOK_PLUGINS = " ".join(NO_HOOK_PLUGINS),
        PLUGIN_SUBPACKAGES = " ".join(PLUGIN_SUBPACKAGES),
        UNLISTED_HOOK_FILES = " ".join(["$(rootpaths %s)" % f for f in UNLISTED_HOOK_FILES]),
    ),
    rustc_flags = ["-Copt-level=3"],
)

# Preserved label that .github/workflows/presubmit.yaml runs (generated from the
# pipeline_unit below) without editing .github/. Contains:
# - :hook_json_helper_test (unit tests for the canonical hook JSON helper)
# - :hooks_drift_test (generator, missing-file, drift, and unlisted-plugin checks)
test_suite(
    name = "shared_files_test",
    tests = [
        ":hook_json_helper_test",
        ":hooks_drift_test",
    ],
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
