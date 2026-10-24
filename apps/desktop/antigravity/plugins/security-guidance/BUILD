# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

"""security-guidance: an Antigravity plugin that scans file edits and shell
commands for security vulnerabilities and leaked secrets.

The plugin is plain ESM JavaScript that Antigravity runs with its own bundled
Node.js, so there is nothing to build; these targets only run the unit tests.
"""

load("@aspect_rules_js//js:defs.bzl", "js_library", "js_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:ignore

package(default_visibility = ["//apps/desktop/antigravity/plugins/security-guidance:__subpackages__"])

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
        ":version_test",
    ],
    tier = "L1",
    timeout_minutes = 15,
)
