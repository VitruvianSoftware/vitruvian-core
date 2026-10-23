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

# //packages/vitruvian-sdk/consumers: who may use the SDK's targets.
#
# ADD A NEW TOOL HERE, and nowhere else in packages/vitruvian-sdk: put its
# package in `tools` below. The SDK's own BUILD names these groups and never a
# product's folder (release_version_test holds it to that).
#
# Why a folder of its own: release-please proposes an SDK release whenever a
# `feat` or `fix` commit changes a file under packages/vitruvian-sdk, and it can
# leave out whole folders only (exclude-paths in ../release-please-config.json),
# never one file. While these lists were in ../BUILD, the pull request that
# added a tool changed the SDK's BUILD and so cut an SDK release with nothing in
# it: 1.1.0 from the GitHub tool (#3193), then 1.2.0 from the HomeSpeaker tool
# (#3211). This folder is in exclude-paths, so letting a tool in releases
# nothing.
#
# Keep it to this one BUILD file. Copybara leaves every BUILD file behind
# (tools/copybara/copy.bara.sky, _monorepo_only), so the public mirror never
# sees this folder; any other file put here would be exported to it.
#
# Hand-written; there is nothing here for Gazelle to write.
# gazelle:ignore

# The Vitruvian desktop app. It links the protocol and reads the protocol's
# examples. It is NOT in `tools`: the app must never come to depend on the kit
# tools are written with (MIT flows into GPL, one way).
package_group(
    name = "app",
    packages = ["//apps/desktop/vitruvian"],
)

# Tools built in this repository against the SDK: the protocol, the kit, the
# `vitruvian-tool` command and the conformance script their folder tests run.
package_group(
    name = "tools",
    packages = [
        "//apps/desktop/home-speaker",
        "//apps/desktop/nexus-agent/macos",
        "//apps/desktop/vitruvian-tool-github",
        "//apps/mobile/android-remote/macmenu",
        "//tools/vitruvian-tv",
    ],
)
