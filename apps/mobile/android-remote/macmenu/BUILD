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

# //apps/mobile/android-remote/macmenu: the Vitruvian Remote menu bar app and
# the self-contained Vitruvian extension (dev.vitruvian.remote).
#
# Both doors share RemoteMenuCore, which supervises the bundled
# vitruvian-remote-agent binary (../macagent), manages settings and pairing,
# and detects when both the standalone app and the Vitruvian extension are
# installed on the same Mac so only the chosen one runs the agent or registers
# the Claude Code permission hook.
#
# Swift has no Gazelle, so this file is hand-written.

load("@build_bazel_rules_apple//apple:macos.bzl", "macos_application")
load("@build_bazel_rules_swift//swift:swift_binary.bzl", "swift_binary")
load("@build_bazel_rules_swift//swift:swift_library.bzl", "swift_library")
load("@build_bazel_rules_swift//swift:swift_test.bzl", "swift_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

swift_library(
    name = "RemoteMenuCore",
    srcs = glob(["Sources/RemoteMenuCore/**/*.swift"]),
    module_name = "RemoteMenuCore",
    target_compatible_with = ["@platforms//os:macos"],
)

swift_library(
    name = "RemoteMenuLib",
    srcs = glob(["Sources/RemoteMenu/**/*.swift"]),
    module_name = "RemoteMenu",
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":RemoteMenuCore"],
)

# macOS-only + manual, like the other Mac apps: the macOS CI leg runs it by
# explicit label, where XCTest is available.
swift_test(
    name = "RemoteMenuTests",
    srcs = glob(
        ["Tests/**/*.swift"],
        exclude = ["Tests/RemoteToolTests/**"],
    ),
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":RemoteMenuCore"],
)

# The Vitruvian Remote extension (dev.vitruvian.remote) for the Vitruvian
# desktop app: island panel, settings panel (every section on one page for an
# app with ui.sections, 4 tabs for one without), 6 commands, supervised
# vitruvian-remote-agent daemon, and standalone/extension coexistence.
swift_library(
    name = "RemoteToolCore",
    srcs = glob(["Sources/RemoteToolCore/**/*.swift"]),
    features = ["swift.enable_v6"],
    module_name = "RemoteToolCore",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":RemoteMenuCore",
        "//packages/vitruvian-sdk:VitruvianToolKit",
        "//packages/vitruvian-sdk:VitruvianToolProtocol",
    ],
)

swift_test(
    name = "RemoteToolTests",
    size = "small",
    srcs = glob(["Tests/RemoteToolTests/**/*.swift"]),
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":RemoteMenuCore",
        ":RemoteToolCore",
        "//packages/vitruvian-sdk:VitruvianToolKit",
        "//packages/vitruvian-sdk:VitruvianToolProtocol",
    ],
)

swift_binary(
    name = "remote-tool",
    srcs = glob(["Sources/RemoteTool/*.swift"]),
    features = ["swift.enable_v6"],
    module_name = "RemoteToolProgram",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":RemoteMenuCore",
        ":RemoteToolCore",
        "//packages/vitruvian-sdk:VitruvianToolKit",
        "//packages/vitruvian-sdk:VitruvianToolProtocol",
    ],
)

# The extension as a self-contained folder the Vitruvian app can install:
# vitruvian-tool.json, bin/tool, and bin/vitruvian-remote-agent.
#
#   bazel build --config=macos-app //apps/mobile/android-remote/macmenu:tool-folder
#
# leaves bazel-bin/apps/mobile/android-remote/macmenu/built/remote/.
genrule(
    name = "tool-folder",
    srcs = [
        "tool/vitruvian-tool.json",
        ":remote-tool",
        "//apps/mobile/android-remote/macagent",
    ],
    outs = [
        "built/remote/vitruvian-tool.json",
        "built/remote/bin/tool",
        "built/remote/bin/vitruvian-remote-agent",
    ],
    cmd = "cp $(location tool/vitruvian-tool.json) $(RULEDIR)/built/remote/vitruvian-tool.json && cp $(location :remote-tool) $(RULEDIR)/built/remote/bin/tool && cp $(location //apps/mobile/android-remote/macagent:macagent) $(RULEDIR)/built/remote/bin/vitruvian-remote-agent && chmod +x $(RULEDIR)/built/remote/bin/tool $(RULEDIR)/built/remote/bin/vitruvian-remote-agent",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
)

# Validates the built folder with `vitruvian-tool validate`, runs the SDK
# conformance suite, and verifies all panels, the settings page with and
# without ui.sections, settings round-trips, QR
# pairing, and standalone/extension coexistence over real JSON-RPC stdio in a
# scratch HOME with a stand-in agent binary.
rust_test(
    name = "tool_conformance_test",
    size = "medium",
    srcs = ["scripts/src/tool_conformance_test.rs"],
    data = [
        "built/remote/vitruvian-tool.json",
        ":tool-folder",
        "//packages/vitruvian-sdk:vitruvian-tool",
    ],
    edition = "2021",
    env = {
        "MANIFEST_PATH": "$(rootpath built/remote/vitruvian-tool.json)",
        "VALIDATE_BIN": "$(rootpath //packages/vitruvian-sdk:vitruvian-tool)",
    },
    rustc_flags = ["-Copt-level=3"],
    tags = [
        "block-network",
        "manual",
    ],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":tool_conformance_lib"],
)

# Verifies that the tool's version matches Version.swift, Info.plist, and
# android-remote's BUILD version, and that release-please-config.json updates
# all of them.
rust_test(
    name = "tool_version_test",
    size = "small",
    srcs = ["scripts/src/tool_version_test.rs"],
    data = [
        "Resources/Info.plist",
        "Sources/RemoteMenuCore/Version.swift",
        "tool/vitruvian-tool.json",
        "//apps/mobile/android-remote:BUILD",
        "//apps/mobile/android-remote:release-please-config.json",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//packages/vitruvian-sdk:conformance_rs_lib"],
)

# The menu finds the agent by the paths the installer writes; fail when they drift.
rust_test(
    name = "paths_match_installer_test",
    size = "small",
    srcs = ["scripts/src/paths_match_installer_test.rs"],
    data = [
        "Sources/RemoteMenuCore/AgentStatus.swift",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//apps/mobile/android-remote/macagent:macagent_scripts_lib"],
)

# The release's zip of the extension (scripts/src/zip_tool), against stand-in
# programs and a stand-in lipo: what it holds, what it is called, the version
# it refuses, and the half-universal build it refuses.
rust_test(
    name = "zip_tool_test",
    size = "small",
    crate = ":zip_tool_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# bazel-bin/apps/mobile/android-remote/macmenu/VitruvianRemote.zip. `manual`
# for the same reason as NexusAgent: macos_application transitions to a darwin
# platform, so target_compatible_with cannot keep it out of a Linux `//...`.
# MenuIcon.png/@2x are template images (black + alpha); macOS tints them for
# light and dark menu bars. Ad-hoc signed.
macos_application(
    name = "VitruvianRemote",
    bundle_id = "com.vitruviansoftware.remote",
    bundle_name = "VitruvianRemote",
    infoplists = ["Resources/Info.plist"],
    minimum_os_version = "14.0",
    resources = [
        "Resources/AppIcon.icns",
        "Resources/MenuIcon.png",
        "Resources/MenuIcon@2x.png",
    ],
    tags = ["manual"],
    visibility = ["//apps/mobile/android-remote:__subpackages__"],
    deps = [":RemoteMenuLib"],
)

# `bazel run --config=macos-app //apps/mobile/android-remote/macmenu:install`
alias(
    name = "install",
    actual = ":install-rs",
    tags = ["manual"],
)

pipeline_unit(
    name = "remote-mac-menu",
    persona = "frontend",
    runner = "xcode-27",
    test_targets = [
        ":RemoteMenuTests",
        ":RemoteToolTests",
        ":paths_match_installer_test",
        ":tool_conformance_test",
        ":tool_version_test",
        ":zip_tool_test",
    ],
    tier = "L1",
    timeout_minutes = 30,
)

# --- Rust ports ---------------------------------------------------------------

rust_library(
    name = "zip_tool_lib",
    srcs = ["scripts/src/zip_tool/lib.rs"],
    crate_name = "zip_tool_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "zip-tool-rs",
    srcs = ["scripts/src/zip_tool/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":zip_tool_lib"],
)

test_suite(
    name = "zip_tool_lib_test",
    tests = [":zip_tool_test"],
)

rust_library(
    name = "install_lib",
    srcs = ["scripts/src/install/lib.rs"],
    crate_name = "install_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "install-rs",
    srcs = ["scripts/src/install/main.rs"],
    data = [
        ":VitruvianRemote",
        "//apps/mobile/android-remote/macagent",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = ["manual"],
    deps = [":install_lib"],
)

rust_test(
    name = "install_lib_test",
    size = "small",
    crate = ":install_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_library(
    name = "publish_tool_lib",
    srcs = ["scripts/src/publish_tool/lib.rs"],
    crate_name = "publish_tool_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":zip_tool_lib"],
)

rust_binary(
    name = "publish-tool-rs",
    srcs = ["scripts/src/publish_tool/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":publish_tool_lib"],
)

rust_test(
    name = "publish_tool_lib_test",
    size = "small",
    crate = ":publish_tool_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "paths_match_installer_rs_test",
    tests = [":paths_match_installer_test"],
)

test_suite(
    name = "tool_version_rs_test",
    tests = [":tool_version_test"],
)

rust_library(
    name = "tool_conformance_lib",
    srcs = ["scripts/src/tool_conformance/lib.rs"],
    crate_name = "tool_conformance_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//packages/vitruvian-sdk:conformance_rs_lib"],
)

rust_binary(
    name = "tool-conformance-rs",
    srcs = ["scripts/src/tool_conformance/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":tool_conformance_lib"],
)

rust_test(
    name = "tool_conformance_lib_test",
    size = "small",
    crate = ":tool_conformance_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "tool_conformance_rs_test",
    tags = ["manual"],
    tests = [":tool_conformance_test"],
)
