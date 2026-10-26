# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware
#
# The GitHub tool for the Vitruvian app: a program of protocol 2 that draws
# the person's pull requests in the island and signs in from a Settings
# panel. Swift has no Gazelle, so this file is written by hand.
#
# Everything here is GPL-3.0-or-later and private: the tool carries code from
# the app's GitHub feature, and nothing MIT may link it. It links the MIT kit,
# which is the one direction allowed. The targets are macOS-only and
# `manual`, like the app's: a Linux `bazel build //...` never names them.
#
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@build_bazel_rules_swift//swift:swift_binary.bzl", "swift_binary")
load("@build_bazel_rules_swift//swift:swift_library.bzl", "swift_library")
load("@build_bazel_rules_swift//swift:swift_test.bzl", "swift_test")
load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

package(default_visibility = ["//apps/desktop/vitruvian-tool-github:__subpackages__"])

MACOS_ONLY = ["@platforms//os:macos"]

# What the tool knows, apart from the link to the app: the repositories and
# their colours, the sign-in, the mouse, the REST client, the words and the
# pages. Pure where it can be, so the tests reach it without a process.
swift_library(
    name = "GitHubToolCore",
    srcs = glob(["Sources/GitHubToolCore/*.swift"]),
    features = ["swift.enable_v6"],
    module_name = "GitHubToolCore",
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
    deps = [
        "//packages/vitruvian-sdk:VitruvianToolKit",
        "//packages/vitruvian-sdk:VitruvianToolProtocol",
    ],
)

# Against a transport that answers itself, a mouse that records what it was
# told, and files in the temporary folder. Nothing here reaches the network.
# The manifest is read to hold the mouse settings' options to the mouse.
swift_test(
    name = "GitHubToolCoreTests",
    size = "small",
    srcs = glob(["Tests/GitHubToolCoreTests/*.swift"]),
    data = ["vitruvian-tool.json"],
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
    deps = [
        ":GitHubToolCore",
        "//packages/vitruvian-sdk:VitruvianToolKit",
        "//packages/vitruvian-sdk:VitruvianToolProtocol",
    ],
)

# The program: the kit's loop around GitHubToolCore, and nothing else.
swift_binary(
    name = "github-tool",
    srcs = glob(["Sources/github-tool/*.swift"]),
    features = ["swift.enable_v6"],
    module_name = "GitHubToolProgram",
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
    deps = [
        ":GitHubToolCore",
        "//packages/vitruvian-sdk:VitruvianToolKit",
        "//packages/vitruvian-sdk:VitruvianToolProtocol",
    ],
)

# The tool as a folder the app can add: the manifest and bin/tool, as the
# mirror's release zips them.
#
#   bazel build --config=macos-app //apps/desktop/vitruvian-tool-github:tool-folder
#
# leaves bazel-bin/apps/desktop/vitruvian-tool-github/built/github/.
genrule(
    name = "tool-folder",
    srcs = [
        "vitruvian-tool.json",
        ":github-tool",
    ],
    outs = [
        "built/github/vitruvian-tool.json",
        "built/github/bin/tool",
    ],
    cmd = "cp $(location vitruvian-tool.json) $(RULEDIR)/built/github/vitruvian-tool.json && cp $(location :github-tool) $(RULEDIR)/built/github/bin/tool",
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
)

# The built folder through `vitruvian-tool validate` and the conformance
# script: the handshake, a command, an unknown command, the island panel
# opened and tapped, refusals, and a clean exit. It starts the real program.
py_test(
    name = "conformance_test",
    size = "small",
    srcs = ["conformance_test.py"],
    args = [
        "$(rootpath built/github/vitruvian-tool.json)",
        "$(rootpath //packages/vitruvian-sdk:conformance/conformance.py)",
        "$(rootpath //packages/vitruvian-sdk:vitruvian-tool)",
    ],
    data = [
        "built/github/vitruvian-tool.json",
        ":tool-folder",
        "//packages/vitruvian-sdk:conformance/conformance.py",
        "//packages/vitruvian-sdk:vitruvian-tool",
    ],
    main = "conformance_test.py",
    tags = [
        "block-network",
        "manual",
    ],
    target_compatible_with = MACOS_ONLY,
)

# The version is one number in three files, and the kit it builds against
# is new enough. Not tied to macOS: the Linux lane runs it too.
py_test(
    name = "version_test",
    size = "small",
    srcs = ["version_test.py"],
    data = [
        ".release-please-manifest.json",
        "Package.swift",
        "Sources/GitHubToolCore/Version.swift",
        "release-please-config.json",
        "vitruvian-tool.json",
    ],
    main = "version_test.py",
)

# The mirror's own workflows (.github/workflows/, which run only in
# VitruvianSoftware/vitruvian-tool-github): release.yml's `detect` and notes
# steps, run as written with bash and git, and what each workflow may write.
# Not tied to macOS. It runs bash and git on the machine, and the remote
# execution image has no jq.
py_test(
    name = "mirror_workflows_test",
    size = "small",
    srcs = ["mirror_workflows_test.py"],
    data = [
        ".github/workflows/ci.yml",
        ".github/workflows/release.yml",
    ],
    main = "mirror_workflows_test.py",
    tags = ["no-remote-exec"],
    deps = ["@pip//pyyaml"],
)

rust_library(
    name = "tests_rs_lib",
    srcs = [
        "tests_rs/src/conformance.rs",
        "tests_rs/src/lib.rs",
        "tests_rs/src/mirror_workflows.rs",
        "tests_rs/src/version.rs",
    ],
    crate_name = "tests_rs_lib",
    crate_root = "tests_rs/src/lib.rs",
    edition = "2021",
    deps = [
        "//packages/vitruvian-sdk:conformance_rs_lib",
        "@crates//:serde_json",
    ],
)

rust_test(
    name = "tests_rs_lib_test",
    size = "small",
    crate = ":tests_rs_lib",
)

rust_test(
    name = "conformance_rs_test",
    size = "small",
    srcs = ["tests_rs/src/conformance_test.rs"],
    data = [
        "built/github/vitruvian-tool.json",
        ":tool-folder",
        "//packages/vitruvian-sdk:conformance_rs",
        "//packages/vitruvian-sdk:vitruvian-tool",
    ],
    edition = "2021",
    env = {
        "MANIFEST_PATH": "$(rootpath built/github/vitruvian-tool.json)",
        "CONFORMANCE_BIN": "$(rootpath //packages/vitruvian-sdk:conformance_rs)",
        "VALIDATE_BIN": "$(rootpath //packages/vitruvian-sdk:vitruvian-tool)",
    },
    tags = [
        "block-network",
        "manual",
    ],
    target_compatible_with = MACOS_ONLY,
    deps = [":tests_rs_lib"],
)

rust_test(
    name = "version_rs_test",
    size = "small",
    srcs = ["tests_rs/src/version_test.rs"],
    data = [
        ".release-please-manifest.json",
        "Package.swift",
        "Sources/GitHubToolCore/Version.swift",
        "release-please-config.json",
        "vitruvian-tool.json",
    ],
    edition = "2021",
    deps = [
        ":tests_rs_lib",
        "@crates//:serde_json",
    ],
)

rust_test(
    name = "mirror_workflows_rs_test",
    size = "small",
    srcs = ["tests_rs/src/mirror_workflows_test.rs"],
    data = [
        ".github/workflows/ci.yml",
        ".github/workflows/release.yml",
    ],
    edition = "2021",
    tags = ["no-remote-exec"],
    deps = [":tests_rs_lib"],
)

pipeline_unit(
    name = "vitruvian-tool-github",
    persona = "platform",
    runner = "xcode-27",
    test_targets = [
        ":GitHubToolCoreTests",
        ":conformance_test",
        ":github-tool",
        ":mirror_workflows_test",
        ":version_test",
    ],
    tier = "L1",
    timeout_minutes = 30,
)
