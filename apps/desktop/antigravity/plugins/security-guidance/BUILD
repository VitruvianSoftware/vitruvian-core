# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

"""security-guidance: an Antigravity plugin that scans file edits and shell
commands for security vulnerabilities and leaked secrets.

The hook is std-only Rust (hooks/src) that hooks/rust-hook.sh compiles with
rustc on the user's machine; the side panel is ESM JavaScript that Antigravity
runs with Node.js. Nothing here is shipped from Bazel: these targets test.
"""

load("@aspect_rules_js//js:defs.bzl", "js_library", "js_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_library.bzl", "sh_library")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:ignore

package(default_visibility = ["//apps/desktop/antigravity/plugins/security-guidance:__subpackages__"])

exports_files([
    "hooks/rust-hook.sh",
    "hooks/security-check.sh",
])

sh_library(
    name = "hook_scripts",
    srcs = glob(
        ["hooks/*.sh"],
        exclude = ["hooks/*_test.sh"],
    ),
)

# The hook Antigravity runs (hooks.json) goes through hooks/rust-hook.sh, which
# compiles hooks/src with a bare rustc on the user's machine. This builds it
# that way with Bazel's rustc, and checks the launcher's caching and its
# fallback when rustc is missing or the build fails.
sh_test(
    name = "rust_hook_test",
    size = "medium",
    srcs = ["hooks/rust-hook_test.sh"],
    data = glob(["hooks/src/**/*.rs"]) + [
        "hooks.json",
        "@rules_rust//rust/toolchain:current_rust_stdlib_files",
        "@rules_rust//rust/toolchain:current_rustc_files",
        "@rules_rust//rust/toolchain:current_rustc_lib_files",
    ],
    env = {
        "HOOKS_JSON": "$(rootpath hooks.json)",
        "PLUGIN_NAME": "security-guidance",
        "REAL_RUSTC": "$(rootpath @rules_rust//rust/toolchain:current_rustc_files)",
    },
    deps = [":hook_scripts"],
)

rust_library(
    name = "security_check_lib",
    srcs = [
        "hooks/src/json.rs",
        "hooks/src/lib.rs",
    ],
    crate_name = "security_check",
    crate_root = "hooks/src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
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

rust_library(
    name = "sidecar_lib",
    srcs = [
        "sidecars/panel/src/lib.rs",
        "sidecars/panel/src/openui.rs",
    ],
    crate_name = "security_guidance_sidecar",
    crate_root = "sidecars/panel/src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        ":security_check_lib",
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "sidecar",
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

test_suite(
    name = "security-check_test",
    tests = [":security_check_lib_test"],
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
        ":rust_hook_test",
        ":security_check_lib_test",
        ":security-check_test",
        ":security_check_lib_test",
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

# What //apps/desktop/antigravity's cross-plugin tests read: the hooks.json
# shape, each hook's fallback, and the files every plugin shares.
js_library(
    name = "conformance_files",
    srcs = glob(
        [
            "hooks.json",
            "hooks/*.sh",
            "hooks/src/json.rs",
        ],
        allow_empty = True,
    ),
    visibility = ["//apps/desktop/antigravity:__pkg__"],
)
