# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

"""pr-watch: an Antigravity plugin that watches pull requests and wakes the
conversation that owns one when its CI starts failing.

The plugin is plain ESM JavaScript that Antigravity runs with its own bundled
Node.js, so there is nothing to build; these targets only run the unit tests.
"""

load("@aspect_rules_js//js:defs.bzl", "js_library", "js_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:ignore

package(default_visibility = ["//apps/desktop/antigravity/plugins/pr-watch:__subpackages__"])

# The watcher's logic. main.mjs is left out on purpose: it imports the
# Antigravity sidecar SDK, which only exists inside the app.
js_library(
    name = "lib",
    srcs = [
        "sidecars/panel/lib/decide.mjs",
        "sidecars/panel/lib/github.mjs",
        "sidecars/panel/lib/pace.mjs",
        "sidecars/panel/lib/store.mjs",
        "sidecars/panel/lib/watcher.mjs",
    ],
)

# Run with Node's built-in `node:test` runner, as nexus-agent's tests are.
js_test(
    name = "decide_test",
    size = "small",
    data = [":lib"],
    entry_point = "sidecars/panel/lib/decide.test.mjs",
)

js_test(
    name = "pace_test",
    size = "small",
    data = [":lib"],
    entry_point = "sidecars/panel/lib/pace.test.mjs",
)

js_test(
    name = "watcher_test",
    size = "small",
    data = [":lib"],
    entry_point = "sidecars/panel/lib/watcher.test.mjs",
)

pipeline_unit(
    name = "antigravity-pr-watch",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":decide_test",
        ":pace_test",
        ":watcher_test",
    ],
    tier = "L1",
    timeout_minutes = 15,
)
