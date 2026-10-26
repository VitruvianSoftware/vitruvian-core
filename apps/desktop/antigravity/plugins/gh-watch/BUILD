# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

"""gh-watch: an Antigravity plugin that watches pull requests and wakes the
conversation that owns one when its CI starts failing.

The plugin is plain ESM JavaScript that Antigravity runs with its own bundled
Node.js, so there is nothing to build; these targets only run the unit tests.
"""

load("@aspect_rules_js//js:defs.bzl", "js_library", "js_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:ignore

package(default_visibility = ["//apps/desktop/antigravity/plugins/gh-watch:__subpackages__"])

exports_files(["hooks/note-pr-create.sh"])

# The watcher's logic. main.mjs is left out on purpose: it imports the
# Antigravity sidecar SDK, which only exists inside the app.
js_library(
    name = "lib",
    srcs = [
        "sidecars/panel/lib/actions.mjs",
        "sidecars/panel/lib/decide.mjs",
        "sidecars/panel/lib/flakes.mjs",
        "sidecars/panel/lib/github.mjs",
        "sidecars/panel/lib/inbox.mjs",
        "sidecars/panel/lib/landing.mjs",
        "sidecars/panel/lib/logs.mjs",
        "sidecars/panel/lib/notices.mjs",
        "sidecars/panel/lib/openui.mjs",
        "sidecars/panel/lib/pace.mjs",
        "sidecars/panel/lib/reviews.mjs",
        "sidecars/panel/lib/store.mjs",
        "sidecars/panel/lib/watcher.mjs",
    ],
)

# Run with Node's built-in `node:test` runner, as nexus-agent's tests are.
js_test(
    name = "actions_test",
    size = "small",
    data = [":lib"],
    entry_point = "sidecars/panel/lib/actions.test.mjs",
)

js_test(
    name = "decide_test",
    size = "small",
    data = [":lib"],
    entry_point = "sidecars/panel/lib/decide.test.mjs",
)

js_test(
    name = "flakes_test",
    size = "small",
    data = [":lib"],
    entry_point = "sidecars/panel/lib/flakes.test.mjs",
)

js_test(
    name = "landing_test",
    size = "small",
    data = [":lib"],
    entry_point = "sidecars/panel/lib/landing.test.mjs",
)

js_test(
    name = "logs_test",
    size = "small",
    data = [":lib"],
    entry_point = "sidecars/panel/lib/logs.test.mjs",
)

js_test(
    name = "notices_test",
    size = "small",
    data = [":lib"],
    entry_point = "sidecars/panel/lib/notices.test.mjs",
)

js_test(
    name = "openui_test",
    size = "small",
    data = [":lib"],
    entry_point = "sidecars/panel/lib/openui.test.mjs",
)

js_test(
    name = "pace_test",
    size = "small",
    data = [":lib"],
    entry_point = "sidecars/panel/lib/pace.test.mjs",
)

js_test(
    name = "reviews_test",
    size = "small",
    data = [":lib"],
    entry_point = "sidecars/panel/lib/reviews.test.mjs",
)

# The files that name the plugin's version. release-please updates them in
# lockstep via release-please-config.json; version_test keeps them in step.
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
    name = "search_test",
    size = "small",
    data = [":lib"],
    entry_point = "sidecars/panel/lib/search.test.mjs",
)

js_test(
    name = "version_test",
    size = "small",
    data = [":release_files"],
    entry_point = "sidecars/panel/lib/version.test.mjs",
)

js_test(
    name = "watcher_test",
    size = "small",
    data = [":lib"],
    entry_point = "sidecars/panel/lib/watcher.test.mjs",
)

rust_library(
    name = "note_pr_create_lib",
    srcs = ["hooks/src/lib.rs"],
    crate_name = "note_pr_create",
    crate_root = "hooks/src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "note-pr-create",
    srcs = ["hooks/src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":note_pr_create_lib"],
)

rust_test(
    name = "note_pr_create_lib_test",
    size = "small",
    crate = ":note_pr_create_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# The hook Antigravity runs after each shell command (hooks.json).
sh_test(
    name = "note-pr-create_test",
    size = "small",
    srcs = ["hooks/note-pr-create_test.sh"],
    data = ["hooks/note-pr-create.sh"],
)

sh_test(
    name = "note-pr-create_rs_test",
    size = "small",
    srcs = ["hooks/note-pr-create_test.sh"],
    args = [
        "$(location :note-pr-create)",
        "$(location hooks/note-pr-create.sh)",
    ],
    data = [
        "hooks/note-pr-create.sh",
        ":note-pr-create",
    ],
)

rust_library(
    name = "sidecar_lib",
    srcs = [
        "sidecars/panel/src/lib.rs",
        "sidecars/panel/src/openui.rs",
    ],
    crate_name = "gh_watch_sidecar",
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
    name = "antigravity-gh-watch",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":actions_test",
        ":decide_test",
        ":flakes_test",
        ":landing_test",
        ":logs_test",
        ":note-pr-create_rs_test",
        ":note-pr-create_test",
        ":note_pr_create_lib_test",
        ":notices_test",
        ":openui_test",
        ":pace_test",
        ":reviews_test",
        ":search_test",
        ":sidecar_lib_test",
        ":version_rs_test",
        ":version_test",
        ":watcher_test",
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
