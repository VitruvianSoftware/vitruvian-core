# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

"""savvy-fleet: an Antigravity plugin for tiered orchestrator-worker subagent
flows and live subagent fleet telemetry.
"""

load("@aspect_rules_js//js:defs.bzl", "js_library", "js_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:ignore

package(default_visibility = ["//apps/desktop/antigravity/plugins/savvy-fleet:__subpackages__"])

exports_files(["hooks/track-subagent.sh"])

rust_library(
    name = "track_subagent_lib",
    srcs = ["hooks/src/lib.rs"],
    crate_name = "track_subagent",
    crate_root = "hooks/src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "track-subagent",
    srcs = ["hooks/src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":track_subagent_lib"],
)

rust_test(
    name = "track_subagent_lib_test",
    size = "small",
    crate = ":track_subagent_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

sh_test(
    name = "track-subagent_test",
    size = "small",
    srcs = ["hooks/track-subagent_test.sh"],
    args = ["$(location hooks/track-subagent.sh)"],
    data = ["hooks/track-subagent.sh"],
)

sh_test(
    name = "track-subagent_rs_test",
    size = "small",
    srcs = ["hooks/track-subagent_test.sh"],
    args = [
        "$(location :track-subagent)",
        "$(location hooks/track-subagent.sh)",
    ],
    data = [
        "hooks/track-subagent.sh",
        ":track-subagent",
    ],
)

js_library(
    name = "lib",
    srcs = [
        "sidecars/panel/lib/core.mjs",
        "sidecars/panel/lib/openui.mjs",
    ],
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

js_test(
    name = "version_test",
    size = "small",
    data = [":release_files"],
    entry_point = "sidecars/panel/lib/version.test.mjs",
)

pipeline_unit(
    name = "antigravity-savvy-fleet",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":core_test",
        ":openui_test",
        ":track-subagent_rs_test",
        ":track-subagent_test",
        ":track_subagent_lib_test",
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
