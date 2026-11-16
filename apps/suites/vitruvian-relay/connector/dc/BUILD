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

# gazelle:ignore

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load("@vrelay_npm//:defs.bzl", "npm_link_all_packages")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# The pinned desktop-commander that `vrelay` runs over stdio, from this
# folder's own lock (@vrelay_npm). The connector takes the package as a runfile
# and starts its dist/index.js with the `node` on PATH (bridge.rs).
npm_link_all_packages(name = "node_modules")

# package.json is read by the connector's tests (which version is pinned), so
# a change here runs them in CI.
exports_files([
    "package.json",
    "pnpm-lock.yaml",
])

alias(
    name = "desktop_commander",
    actual = ":node_modules/@wonderwhy-er/desktop-commander",
    visibility = [
        "//apps/suites/vitruvian-relay/connector:__pkg__",
        "//apps/suites/vitruvian-relay/connector/scripts:__pkg__",
    ],
)

# The pinned package fetches and links from this folder's lock. Its own unit,
# so the npm fetch runs only for changes here (the planner picks units by the
# tests a change reaches), not for every connector change. The installer's
# placement test (an installed copy holds a working rg) rides along: it
# reaches only the package and scripts/src/layout.rs.
build_test(
    name = "desktop_commander_builds",
    targets = [":desktop_commander"],
)

pipeline_unit(
    name = "vrelay-dc",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":desktop_commander_builds",
        "//apps/suites/vitruvian-relay/connector/scripts:package_layout_clippy",
        "//apps/suites/vitruvian-relay/connector/scripts:package_layout_test",
    ],
    tier = "L1",
    timeout_minutes = 15,
)
