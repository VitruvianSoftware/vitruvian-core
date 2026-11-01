# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

"""Checks across the Antigravity plugins under plugins/."""

load("@aspect_rules_js//js:defs.bzl", "js_test")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
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

# Every hooks.json has the shape Antigravity loads (a wrong entry gets the
# whole file skipped), and no PreToolUse hook can fall back to `{}`, which
# Antigravity treats as a denial.
js_test(
    name = "hooks_json_test",
    size = "small",
    args = ["$(rootpaths %s)" % c for c in CONFORMANCE],
    data = CONFORMANCE,
    entry_point = "hooks_json.test.mjs",
)

# The files every plugin carries its own copy of are identical.
sh_test(
    name = "shared_files_test",
    size = "small",
    srcs = ["shared_files_test.sh"],
    args = ["$(rootpaths %s)" % c for c in CONFORMANCE],
    data = CONFORMANCE,
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
