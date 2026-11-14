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

"""Vitruvian TV extension (dev.vitruvian.tv) for Sony Google TV control over ADB.

A Rust program (src/main.rs) on the SDK's Rust kit. Hand-written: Gazelle
has no Rust here. It adds no crate: the kit's serde and serde_json come from
the crate universe @crates, so Cargo.lock and MODULE.bazel stay as they are.
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

package(default_visibility = ["//apps/extensions/atrium/vitruvian-tv:__subpackages__"])

rust_binary(
    name = "vitruvian_tv",
    srcs = ["src/main.rs"],
    edition = "2021",
    deps = [
        "//packages/vitruvian-sdk/kits/rust:vitruvian_tool_kit",
        "@crates//:serde_json",
    ],
)

# The #[cfg(test)] unit tests in src/main.rs, adb stood in by a mock.
rust_test(
    name = "vitruvian_tv_unit_test",
    size = "small",
    crate = ":vitruvian_tv",
)

# The extension as a self-contained folder the Vitruvian app can install:
# vitruvian-tool.json and bin/tool, the program its runtime.exec names.
#
#   bazel build //apps/extensions/atrium/vitruvian-tv:tool-folder
#
# leaves bazel-bin/apps/extensions/atrium/vitruvian-tv/built/vitruvian-tv/.
genrule(
    name = "tool-folder",
    srcs = [
        "vitruvian-tool.json",
        ":vitruvian_tv",
    ],
    outs = [
        "built/vitruvian-tv/vitruvian-tool.json",
        "built/vitruvian-tv/bin/tool",
    ],
    cmd = " && ".join([
        "cp $(location vitruvian-tool.json) $(RULEDIR)/built/vitruvian-tv/vitruvian-tool.json",
        "cp $(location :vitruvian_tv) $(RULEDIR)/built/vitruvian-tv/bin/tool",
        "chmod 755 $(RULEDIR)/built/vitruvian-tv/bin/tool",
    ]),
    visibility = ["//visibility:public"],
)

# The SDK's conformance binary against the built folder: the Rust program
# plays the app's side of the protocol end to end.
rust_test(
    name = "vitruvian_tv_test",
    size = "small",
    srcs = ["scripts/src/vitruvian_tv_test.rs"],
    data = [
        "built/vitruvian-tv/vitruvian-tool.json",
        ":tool-folder",
        "//packages/vitruvian-sdk:conformance",
    ],
    edition = "2021",
    env = {
        "MANIFEST_PATH": "$(rootpath built/vitruvian-tv/vitruvian-tool.json)",
        "CONFORMANCE_BIN": "$(rootpath //packages/vitruvian-sdk:conformance)",
    },
)

rust_library(
    name = "publish_tool_lib",
    srcs = ["scripts/src/publish_tool/lib.rs"],
    crate_name = "publish_tool_lib",
    edition = "2021",
    deps = ["@crates//:serde_json"],
)

rust_binary(
    name = "publish-tool",
    srcs = ["scripts/src/publish_tool/main.rs"],
    edition = "2021",
    deps = [":publish_tool_lib"],
)

rust_test(
    name = "publish_tool_lib_test",
    size = "small",
    crate = ":publish_tool_lib",
)

# Holds vitruvian-tool.json to release-please's JSON layout (every non-empty
# array one item a line) and checks its version matches release-please.
rust_test(
    name = "version_test",
    size = "small",
    srcs = ["scripts/src/version_test.rs"],
    data = [
        ".release-please-manifest.json",
        "release-please-config.json",
        "vitruvian-tool.json",
    ],
    edition = "2021",
    env = {
        "MANIFEST_PATH": "$(rootpath vitruvian-tool.json)",
        "RP_CONFIG_PATH": "$(rootpath release-please-config.json)",
        "RP_MANIFEST_PATH": "$(rootpath .release-please-manifest.json)",
    },
    deps = [
        "//packages/vitruvian-sdk:conformance_lib",
        "@crates//:serde_json",
    ],
)

# bin/tool's oldest macOS (LC_BUILD_VERSION minos) is no newer than the app's
# LSMinimumSystemVersion: the check catalog-bump refused 0.1.1 and 0.1.2 on
# (#4704, #4796), run before a release instead of after. Mac only: elsewhere
# bin/tool is not a Mach-O.
rust_test(
    name = "minos_test",
    size = "small",
    srcs = ["scripts/src/minos_test.rs"],
    data = [
        "built/vitruvian-tv/bin/tool",
        "//catalog:app_info_plist",
    ],
    edition = "2021",
    env = {
        "TOOL_PATH": "$(rootpath built/vitruvian-tv/bin/tool)",
        "APP_INFO_PATH": "$(rootpath //catalog:app_info_plist)",
    },
    target_compatible_with = ["@platforms//os:macos"],
    deps = ["//catalog:catalog_lib"],
)
