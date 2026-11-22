# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""The vitruvian-orchestrator plugin: MCP telemetry server, live sidecar panel,
and the files the site registry reads.
"""

load("@aspect_rules_js//js:defs.bzl", "js_library", "js_test")
load("@rules_rust//rust:defs.bzl", "rust_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:ignore

package(default_visibility = ["//apps/antigravity/plugins/vitruvian-orchestrator:__subpackages__"])

js_library(
    name = "orchestrator_core_lib",
    srcs = [
        "sidecars/panel/lib/orchestrator-core.mjs",
        "sidecars/panel/lib/prices.mjs",
        "sidecars/panel/lib/tier-defaults.mjs",
    ],
)

js_library(
    name = "server_lib",
    srcs = ["mcp/server.mjs"],
    data = ["plugin.json"],
    deps = [":orchestrator_core_lib"],
)

js_test(
    name = "server_test",
    size = "small",
    data = [
        "sidecars/panel/testdata/sample-flow.jsonl",
        ":server_lib",
        "//:.agents/team.json",
        "//:roster_generated_agents",
    ] + glob(
        ["agents/*.md"],
        allow_empty = True,
    ),
    entry_point = "mcp/server.test.mjs",
    no_copy_to_bin = [
        "//:.agents/team.json",
        "//:roster_generated_agents",
    ],
)

js_library(
    name = "panel_lib",
    srcs = ["sidecars/panel/main.mjs"],
    data = [
        "plugin.json",
        "sidecars/panel/app.js",
        "sidecars/panel/index.html",
        "sidecars/panel/styles.css",
        "sidecars/panel/testdata/sample-flow.jsonl",
    ],
    deps = [":orchestrator_core_lib"],
)

js_test(
    name = "panel_test",
    size = "small",
    data = [
        "README.md",
        "sidecars/panel/README.md",
        ":panel_lib",
        ":server_lib",
    ],
    entry_point = "sidecars/panel/main.test.mjs",
)

js_test(
    name = "drift_test",
    size = "small",
    data = [
        "mcp_config.json",
        "plugin.json",
        "rules/AGENTS.md",
        "skills/orchestrate/SKILL.md",
        ":server_lib",
        "//:.agents/roster/generic/roles.tsv",
        "//:.agents/roster/tiers.tsv",
    ] + glob(
        ["agents/*.md"],
        allow_empty = True,
    ),
    entry_point = "drift.test.mjs",
    no_copy_to_bin = [
        "//:.agents/roster/generic/roles.tsv",
        "//:.agents/roster/tiers.tsv",
    ],
)

filegroup(
    name = "generated_generic_files",
    srcs = glob(
        [
            "agents/*.md",
            "skills/orchestrate/SKILL.md",
            "skills/team-setup/SKILL.md",
        ],
        allow_empty = True,
    ),
    visibility = ["//tools/agent-roster:__pkg__"],
)

filegroup(
    name = "site_sources",
    srcs = glob(
        [
            "plugin.json",
            ".claude-plugin/plugin.json",
            "mcp_config.json",
            "sidecars/*/sidecar.json",
            "skills/*/SKILL.md",
            "rules/*.md",
        ],
        allow_empty = True,
    ),
    visibility = [
        "//apps/antigravity/plugins/ext-marketplace:__pkg__",
        "//tools/sync-site-tools:__pkg__",
    ],
)

# The release-please layout (plugin.json, the panel's package.json, the manifest and the
# changelog at one version), checked by the test every Antigravity plugin shares.
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

rust_test(
    name = "version_rs_test",
    size = "small",
    srcs = ["//apps/antigravity:plugin_version_test.rs"],
    crate_root = "//apps/antigravity:plugin_version_test.rs",
    data = [":release_files"],
    edition = "2021",
    rustc_env = {
        "PLUGIN_NAME": "vitruvian-orchestrator",
        "PLUGIN_PKG": package_name(),
    },
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

pipeline_unit(
    name = "antigravity-vitruvian-orchestrator",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":drift_test",
        ":panel_test",
        ":server_test",
        ":version_rs_test",
    ],
    tier = "L1",
    timeout_minutes = 15,
)
