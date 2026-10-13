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
swift_test(
    name = "GitHubToolCoreTests",
    size = "small",
    srcs = glob(["Tests/GitHubToolCoreTests/*.swift"]),
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
    deps = [
        ":GitHubToolCore",
        "//packages/vitruvian-sdk:VitruvianToolKit",
        "//packages/vitruvian-sdk:VitruvianToolProtocol",
    ],
)
