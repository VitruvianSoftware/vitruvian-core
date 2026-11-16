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

load("@vrelay_npm//:defs.bzl", "npm_link_all_packages")

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
    visibility = ["//apps/suites/vitruvian-relay/connector:__pkg__"],
)
