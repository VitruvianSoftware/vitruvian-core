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

"""Shared pure state machine, burn-down, task board, and cost estimation for
vitruvian-orchestrator live panels across Claude Code, Antigravity, and OpenCode.
"""

load("@aspect_rules_js//js:defs.bzl", "js_library", "js_test")

# gazelle:ignore
# gazelle:exclude src

package(default_visibility = ["//:__subpackages__"])

exports_files([
    "src/core.mjs",
    "src/prices.mjs",
])

js_library(
    name = "lib",
    srcs = [
        "src/core.mjs",
        "src/prices.mjs",
    ],
)

js_test(
    name = "core_test",
    size = "small",
    data = [
        ":lib",
        "//apps/claude-code/plugins/vitruvian-orchestrator:README.md",
    ],
    entry_point = "src/core.test.mjs",
    no_copy_to_bin = [
        "//apps/claude-code/plugins/vitruvian-orchestrator:README.md",
    ],
)
