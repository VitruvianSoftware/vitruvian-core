# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

"""ext-marketplace: an Antigravity plugin providing the Extensions Marketplace
catalog and installed plugin manager sidecar.
"""

load("@aspect_rules_js//js:defs.bzl", "js_library", "js_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:ignore

package(default_visibility = ["//apps/desktop/antigravity/plugins/ext-marketplace:__subpackages__"])

exports_files(["hooks/note-plugin-cmd.sh"])

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

rust_library(
    name = "note_plugin_cmd_lib",
    srcs = ["hooks/src/lib.rs"],
    crate_name = "note_plugin_cmd",
    crate_root = "hooks/src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "note-plugin-cmd",
    srcs = ["hooks/src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":note_plugin_cmd_lib"],
)

rust_test(
    name = "note_plugin_cmd_lib_test",
    size = "small",
    crate = ":note_plugin_cmd_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

sh_test(
    name = "note-plugin-cmd_test",
    size = "small",
    srcs = ["hooks/note-plugin-cmd_test.sh"],
    args = ["$(location hooks/note-plugin-cmd.sh)"],
    data = ["hooks/note-plugin-cmd.sh"],
)

sh_test(
    name = "note-plugin-cmd_rs_test",
    size = "small",
    srcs = ["hooks/note-plugin-cmd_test.sh"],
    args = [
        "$(location :note-plugin-cmd)",
        "$(location hooks/note-plugin-cmd.sh)",
    ],
    data = [
        "hooks/note-plugin-cmd.sh",
        ":note-plugin-cmd",
    ],
)

pipeline_unit(
    name = "antigravity-ext-marketplace",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":core_test",
        ":note-plugin-cmd_rs_test",
        ":note-plugin-cmd_test",
        ":note_plugin_cmd_lib_test",
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
