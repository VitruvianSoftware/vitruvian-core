# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

<<<<<<<< HEAD:apps/opencode/plugins/vitruvian-orchestrator/BUILD
load("@aspect_rules_js//js:defs.bzl", "js_library", "js_test")

package(default_visibility = ["//visibility:public"])

# gazelle:ignore

js_library(
    name = "adapter",
    srcs = [
        "lib/adapter.mjs",
        "lib/orchestrator-core.mjs",
    ],
)

js_test(
    name = "adapter_test",
    data = [":adapter"],
    entry_point = "lib/adapter.test.mjs",
    node_options = ["--test"],
========
"""The vitruvian-orchestrator plugin: MCP telemetry server, live sidecar panel,
and the files the site registry reads.
"""

load("@aspect_rules_js//js:defs.bzl", "js_library", "js_test")

# gazelle:ignore

package(default_visibility = ["//apps/desktop/antigravity/plugins/vitruvian-orchestrator:__subpackages__"])

js_library(
    name = "orchestrator_core_lib",
    srcs = ["sidecars/panel/lib/orchestrator-core.mjs"],
)

js_library(
    name = "server_lib",
    srcs = ["mcp/server.mjs"],
    deps = [":orchestrator_core_lib"],
)

js_test(
    name = "server_test",
    size = "small",
    data = [":server_lib"],
    entry_point = "mcp/server.test.mjs",
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
        ":panel_lib",
        ":server_lib",
    ],
    entry_point = "sidecars/panel/main.test.mjs",
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
    visibility = ["//tools/sync-site-tools:__pkg__"],
>>>>>>>> origin/main:apps/desktop/antigravity/plugins/vitruvian-orchestrator/BUILD
)
