# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

"""security-guidance: an Antigravity plugin that scans file edits and shell
commands for security vulnerabilities and leaked secrets.

The plugin is plain ESM JavaScript that Antigravity runs with its own bundled
Node.js, so there is nothing to build; these targets only run the unit tests.
"""

load("@aspect_rules_js//js:defs.bzl", "js_library", "js_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:ignore

package(default_visibility = ["//apps/desktop/antigravity/plugins/security-guidance:__subpackages__"])

exports_files(["hooks/security-check.sh"])

rust_library(
    name = "security_check_lib",
    srcs = ["hooks/src/lib.rs"],
    crate_name = "security_check",
    crate_root = "hooks/src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "security-check",
    srcs = ["hooks/src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":security_check_lib"],
)

rust_test(
    name = "security_check_lib_test",
    size = "small",
    crate = ":security_check_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

sh_test(
    name = "security-check_test",
    size = "small",
    srcs = ["hooks/security-check_test.sh"],
    args = ["$(location hooks/security-check.sh)"],
    data = [
        "hooks/security-check.sh",
        "sidecars/panel/lib/core.mjs",
        "@nodejs_toolchains//:resolved_toolchain",
    ],
    env = {"VITRUVIAN_NODE": "$(NODE_PATH)"},
    toolchains = ["@nodejs_toolchains//:resolved_toolchain"],
)

sh_test(
    name = "security-check_rs_test",
    size = "small",
    srcs = ["hooks/security-check_test.sh"],
    args = [
        "$(location :security-check)",
        "$(location hooks/security-check.sh)",
    ],
    data = [
        "hooks/security-check.sh",
        "sidecars/panel/lib/core.mjs",
        ":security-check",
        "@nodejs_toolchains//:resolved_toolchain",
    ],
    env = {"VITRUVIAN_NODE": "$(NODE_PATH)"},
    toolchains = ["@nodejs_toolchains//:resolved_toolchain"],
)

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
    name = "antigravity-security-guidance",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":core_test",
        ":openui_test",
        ":security-check_rs_test",
        ":security-check_test",
        ":security_check_lib_test",
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
