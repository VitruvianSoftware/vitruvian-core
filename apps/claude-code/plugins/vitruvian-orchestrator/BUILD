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

# gazelle:ignore
# The mod (hooks/) runs inside Claude Code, not under Bazel; its tests run with
# `claude plugin test`. Keep gazelle from generating js targets for it.
# gazelle:exclude hooks
# gazelle:exclude tsconfig.json

exports_files(
    ["README.md"],
    visibility = ["//packages/orchestrator-core:__pkg__"],
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
