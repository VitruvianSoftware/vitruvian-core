# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

"""ralph-loop: an Antigravity plugin that drives self-referential iterative
development loops until completion criteria are met.
"""

load("@aspect_rules_js//js:defs.bzl", "js_library", "js_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:ignore

package(default_visibility = ["//apps/desktop/antigravity/plugins/ralph-loop:__subpackages__"])

exports_files(["hooks/ralph-stop.sh"])

rust_library(
    name = "ralph_stop_lib",
    srcs = ["hooks/src/lib.rs"],
    crate_name = "ralph_stop",
    crate_root = "hooks/src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["@crates//:serde_json"],
)

rust_binary(
    name = "ralph-stop",
    srcs = ["hooks/src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":ralph_stop_lib"],
)

rust_test(
    name = "ralph_stop_lib_test",
    size = "small",
    crate = ":ralph_stop_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_library(
    name = "sidecar_lib",
    srcs = [
        "sidecars/panel/src/lib.rs",
        "sidecars/panel/src/openui.rs",
    ],
    crate_name = "ralph_loop_sidecar",
    crate_root = "sidecars/panel/src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "sidecar-rs",
    srcs = ["sidecars/panel/src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        ":sidecar_lib",
        "@crates//:serde_json",
    ],
)

rust_test(
    name = "sidecar_lib_test",
    size = "small",
    crate = ":sidecar_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_test(
    name = "version_rs_test",
    size = "small",
    srcs = ["sidecars/panel/src/version_test.rs"],
    data = [":release_files"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

sh_test(
    name = "ralph-stop_test",
    size = "small",
    srcs = ["hooks/ralph-stop_test.sh"],
    args = ["$(location hooks/ralph-stop.sh)"],
    data = [
        "hooks/ralph-stop.sh",
        "@nodejs_toolchains//:resolved_toolchain",
    ],
    env = {"VITRUVIAN_NODE": "$(NODE_PATH)"},
    toolchains = ["@nodejs_toolchains//:resolved_toolchain"],
)

sh_test(
    name = "ralph-stop_rs_test",
    size = "small",
    srcs = ["hooks/ralph-stop_test.sh"],
    args = [
        "$(location :ralph-stop)",
        "$(location hooks/ralph-stop.sh)",
    ],
    data = [
        "hooks/ralph-stop.sh",
        ":ralph-stop",
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
    name = "antigravity-ralph-loop",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":core_test",
        ":openui_test",
        ":ralph-stop_rs_test",
        ":ralph-stop_test",
        ":ralph_stop_lib_test",
        ":sidecar_lib_test",
        ":version_rs_test",
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
