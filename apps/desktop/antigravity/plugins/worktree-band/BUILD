# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

"""worktree-band: an Antigravity plugin that tracks git worktrees, pull request
status, and Bazel output-base disk usage with safe post-merge cleanup.
"""

load("@aspect_rules_js//js:defs.bzl", "js_library", "js_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:ignore

package(default_visibility = ["//apps/desktop/antigravity/plugins/worktree-band:__subpackages__"])

js_library(
    name = "lib",
    srcs = [
        "sidecars/panel/lib/core.mjs",
        "sidecars/panel/lib/openui.mjs",
    ],
)

js_test(
    name = "core_test",
    size = "small",
    data = [":lib"],
    entry_point = "sidecars/panel/lib/core.test.mjs",
)

js_test(
    name = "openui_test",
    size = "small",
    data = [":lib"],
    entry_point = "sidecars/panel/lib/openui.test.mjs",
)

js_library(
    name = "release_files",
    srcs = [
        ".release-please-manifest.json",
        "CHANGELOG.md",
        "plugin.json",
        "release-please-config.json",
        "sidecars/panel/package.json",
    ],
)

js_test(
    name = "version_test",
    size = "small",
    data = [":release_files"],
    entry_point = "sidecars/panel/lib/version.test.mjs",
)

pipeline_unit(
    name = "antigravity-worktree-band",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":core_test",
        ":openui_test",
        ":version_test",
    ],
    tier = "L1",
    timeout_minutes = 15,
)

filegroup(
    name = "site_sources",
    srcs = glob(
        [
            "plugin.json",
            ".claude-plugin/plugin.json",
            "hooks.json",
            ".mcp.json",
            "mcp.json",
            "sidecars/*/sidecar.json",
            "skills/*/SKILL.md",
            "rules/*.md",
        ],
        allow_empty = True,
    ),
    visibility = ["//tools/sync-site-tools:__pkg__"],
)
