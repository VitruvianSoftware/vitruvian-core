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

"""The vitruvian-orchestrator plugin: the files the site registry reads."""

load("@aspect_rules_js//js:defs.bzl", "js_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:ignore
# The mod (hooks/) runs inside Claude Code, not under Bazel; its tests run with
# `claude plugin test`. Keep gazelle from generating js targets for it.
# gazelle:exclude hooks
# gazelle:exclude tsconfig.json

exports_files(
    ["README.md"],
    visibility = ["//packages/orchestrator-core:__pkg__"],
)

js_test(
    name = "drift_test",
    size = "small",
    data = [
        "README.md",
        "hooks/lib/orchestrator-core.mjs",
        "hooks/lib/prices.mjs",
        "hooks/register.tsx",
        "skills/orchestrate/SKILL.md",
        "//:.agents/roster/generic/roles.tsv",
        "//:.agents/roster/tiers.tsv",
        "//:.agents/team.json",
        "//:roster_generated_agents",
        "//apps/claude-code/plugins/vitruvian-orchestrator/types:index.d.ts",
    ] + glob(
        ["agents/*.md"],
        allow_empty = True,
    ),
    entry_point = "drift.test.mjs",
    no_copy_to_bin = [
        "//:.agents/roster/generic/roles.tsv",
        "//:.agents/roster/tiers.tsv",
        "//:.agents/team.json",
        "//:roster_generated_agents",
        "//apps/claude-code/plugins/vitruvian-orchestrator/types:index.d.ts",
    ],
)

js_test(
    name = "version_test",
    size = "small",
    data = [
        ".claude-plugin/plugin.json",
        ".release-please-manifest.json",
        "CHANGELOG.md",
        "release-please-config.json",
    ],
    entry_point = "version.test.mjs",
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
            "skills/*/SKILL.md",
        ],
        allow_empty = True,
    ),
    visibility = ["//tools/sync-site-tools:__pkg__"],
)

pipeline_unit(
    name = "claude-code-vitruvian-orchestrator",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":drift_test",
        ":version_test",
    ],
    tier = "L1",
    timeout_minutes = 15,
)
