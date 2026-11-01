# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

"""worktree-band: an Antigravity plugin that tracks git worktrees, pull request
status, and Bazel output-base disk usage with safe post-merge cleanup.

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

package(default_visibility = ["//apps/desktop/antigravity/plugins/worktree-band:__subpackages__"])

exports_files([
    "hooks/session-worktree.sh",
    "hooks/rust-hook.sh",
])

sh_library(
    name = "hook_scripts",
    srcs = glob(
        ["hooks/*.sh"],
        exclude = ["hooks/*_test.sh"],
    ),
)

# The hooks Antigravity runs (hooks.json) go through hooks/rust-hook.sh, which
# compiles hooks/src with a bare rustc on the user's machine. This builds them
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
        "PLUGIN_NAME": "worktree-band",
        "REAL_RUSTC": "$(rootpath @rules_rust//rust/toolchain:current_rustc_files)",
    },
    deps = [":hook_scripts"],
)

rust_library(
    name = "session_worktree_lib",
    srcs = ["hooks/src/lib.rs"],
    crate_name = "session_worktree",
    crate_root = "hooks/src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "session-worktree",
    srcs = ["hooks/src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":session_worktree_lib"],
)

rust_test(
    name = "session_worktree_lib_test",
    size = "small",
    crate = ":session_worktree_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "session-worktree_test",
    tests = [":session_worktree_lib_test"],
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

filegroup(
    name = "release_files",
    srcs = [
        ".release-please-manifest.json",
        "CHANGELOG.md",
        "plugin.json",
        "release-please-config.json",
        "sidecars/panel/package.json",
    ],
)

rust_library(
    name = "sidecar_lib",
    srcs = [
        "sidecars/panel/src/lib.rs",
        "sidecars/panel/src/openui.rs",
    ],
    crate_name = "worktree_band_sidecar",
    crate_root = "sidecars/panel/src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
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
    crate_root = "sidecars/panel/src/version_test.rs",
    data = [":release_files"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

pipeline_unit(
    name = "antigravity-worktree-band",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":core_test",
        ":openui_test",
        ":rust_hook_test",
        ":session_worktree_lib_test",
        ":session-worktree_test",
        ":session_worktree_lib_test",
        ":sidecar_lib_test",
        ":version_rs_test",
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
filegroup(
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
