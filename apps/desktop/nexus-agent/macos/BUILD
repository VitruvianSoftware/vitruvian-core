load("@build_bazel_rules_apple//apple:macos.bzl", "macos_application")
load("@build_bazel_rules_swift//swift:swift_library.bzl", "swift_library")
load("@build_bazel_rules_swift//swift:swift_test.bzl", "swift_test")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# The shared core: built into this app AND into the Vitruvian desktop app
# (docs/superpowers/specs/2026-10-08-nexus-agent-shared-library-design.md).
# Swift 6 mode because Vitruvian's Core module is. Nothing here may import a
# Vitruvian module: the dependency runs one way, MIT into GPL.
# It is a module of its own because the app target has `@main`: linking that
# into the XCTest target gives a duplicate `_main` symbol (#807), so any code
# the tests need lives here.
swift_library(
    name = "NexusAgentCore",
    srcs = [":shared_sources"],
    features = ["swift.enable_v6"],
    module_name = "NexusAgentCore",
    target_compatible_with = ["@platforms//os:macos"],
    visibility = [
        "//apps/desktop/nexus-agent:__subpackages__",
        "//apps/desktop/vitruvian:__pkg__",
    ],
)

# The one list of shared source files: it is both what NexusAgentCore compiles
# and what Vitruvian's pin hashes, so the two cannot drift apart.
filegroup(
    name = "shared_sources",
    srcs = glob(["Sources/NexusAgentCore/**/*.swift"]),
    visibility = ["//apps/desktop/vitruvian:__pkg__"],
)

# The shared chat view: the SwiftUI the Vitruvian desktop app shows its Nexus
# Agent chat with, and this app its own (ChatWindowController.swift hosts it).
# It takes the engine, its text and what differs between the apps as inputs,
# so, like the core, it may import no Vitruvian module. A module of its own so
# that the core stays free of SwiftUI.
#
# `data` is what the library needs beside it at run time: both apps' bundles
# get these files in Contents/Resources, where NexusAgentMermaidPage looks.
swift_library(
    name = "NexusAgentUI",
    srcs = [":shared_ui_sources"],
    data = [":shared_ui_resources"],
    features = ["swift.enable_v6"],
    module_name = "NexusAgentUI",
    target_compatible_with = ["@platforms//os:macos"],
    visibility = [
        "//apps/desktop/nexus-agent:__subpackages__",
        "//apps/desktop/vitruvian:__pkg__",
    ],
    deps = [":NexusAgentCore"],
)

# As `shared_sources`: what NexusAgentUI compiles and what Vitruvian's pin
# hashes are this one list.
filegroup(
    name = "shared_ui_sources",
    srcs = glob(["Sources/NexusAgentUI/**/*.swift"]),
    visibility = ["//apps/desktop/vitruvian:__pkg__"],
)

# What the chat view ships beside its code: the copy of Mermaid the diagram
# cards draw with, and Mermaid's licence (../THIRD_PARTY_NOTICES.md). Listed by
# name, as Package.swift lists them, so a file added to the folder is shipped
# by both builds or by neither. Vitruvian's pin hashes these too: a newer
# Mermaid is a change to that app.
filegroup(
    name = "shared_ui_resources",
    srcs = [
        "Sources/NexusAgentUI/Resources/mermaid.min.js",
        "Sources/NexusAgentUI/Resources/mermaid-LICENSE.txt",
    ],
    visibility = ["//apps/desktop/vitruvian:__pkg__"],
)

# NexusAgent is a dependency-free SwiftUI/AppKit menu-bar agent (LSUIElement).
# Swift has no Gazelle, so this BUILD file is hand-written. The library is
# constrained to macOS so a Linux `bazel build //...` skips it instead of
# failing to find an Apple toolchain.
swift_library(
    name = "NexusAgentLib",
    srcs = glob(["Sources/NexusAgent/**/*.swift"]),
    module_name = "NexusAgent",
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":NexusAgentCore",
        ":NexusAgentUI",
    ],
)

alias(
    name = "NexusAgent_lib",
    actual = ":NexusAgentLib",
    deprecation = "Target :NexusAgent_lib is deprecated. Use :NexusAgentLib instead. Will be removed in Phase 5.",
)

# Unit tests for the pure-logic pieces. Depends on the two shared libraries only
# (NOT the app lib), so no `@main` is linked in. macOS-only + `manual` like the app bundle,
# so a Linux `bazel build/test //...` skips it; the macОС CI leg runs it by
# explicit label (#807).
swift_test(
    name = "NexusAgentTests",
    srcs = glob(["Tests/**/*.swift"]),
    # EngineHostTests reads the shared sources to prove they name no app's
    # saved-settings key and only run tools that exist. SharedCasesTests reads
    # the examples it shares with the bot's tests. ChatSymbolsTests reads the
    # chat view's sources to prove every SF Symbol it draws exists.
    # MermaidPageTests draws a diagram with the shipped copy of Mermaid.
    data = [
        ":shared_sources",
        ":shared_ui_resources",
        ":shared_ui_sources",
        "//apps/desktop/nexus-agent:testdata_files",
    ],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":NexusAgentCore",
        ":NexusAgentUI",
    ],
)

alias(
    name = "NexusAgent_tests",
    actual = ":NexusAgentTests",
    deprecation = "Target :NexusAgent_tests is deprecated. Use :NexusAgentTests instead. Will be removed in Phase 5.",
)

# Produces bazel-bin/nexus-agent/macos/NexusAgent.app.
#
# `tags = ["manual"]` keeps this out of wildcard builds (`//...`, `//nexus-agent/...`)
# so a Linux `bazel build //...` skips it. `target_compatible_with` does NOT work
# here: macos_application applies an incoming transition to an apple `darwin_*`
# platform, and target_compatible_with is evaluated AFTER that transition, so the
# macOS constraint is always satisfied and the target is never skipped on Linux --
# it instead fails toolchain resolution ("No matching toolchains found"). The macOS
# CI leg builds this by explicit label, which ignores `manual`.
#
# AppIcon.icns is passed as a loose `resources` file (NOT `app_icons`): the
# Info.plist references the icon via `CFBundleIconFile=AppIcon`, and `app_icons`
# would require an `*.xcassets/*.appiconset` asset catalog compiled by `actool`,
# which is only available with a full Xcode install. A loose .icns avoids that.
#
# No `provisioning_profile` or signing identity is configured, so rules_apple
# ad-hoc signs the bundle by default ("codesign --identity -").
macos_application(
    name = "NexusAgent",
    bundle_id = "com.vitruviansoftware.nexusagent",
    infoplists = ["Resources/Info.plist"],
    minimum_os_version = "14.0",
    resources = ["Resources/AppIcon.icns"],
    tags = ["manual"],
    # App-internal (#82): CI builds this by explicit label, which ignores
    # visibility; nothing outside //apps/desktop/nexus-agent may dep the bundle.
    visibility = ["//apps/desktop/nexus-agent:__subpackages__"],
    deps = [":NexusAgentLib"],
)

sh_test(
    name = "mirror_build_test",
    size = "large",
    srcs = ["scripts/mirror_build_test.sh"],
    # The tests and the examples they share with the bot as well: the script
    # also runs `swift test`. The release script and what it copies, because
    # the script also packages the build the way a release does.
    data = [
        "Package.swift",
        "scripts/bundle.sh",
    ] + glob([
        "Resources/**",
        "Sources/**",
        "Tests/**",
    ]) + ["//apps/desktop/nexus-agent:testdata_files"],
    env_inherit = ["DEVELOPER_DIR"],
    # SwiftPM wants the real toolchain and its own sandbox: run outside Bazel's.
    tags = [
        "local",
        "manual",
    ],
    target_compatible_with = ["@platforms//os:macos"],
)

pipeline_unit(
    name = "nexus-agent-macos",
    depends_on = ["nexus-agent-src"],
    persona = "frontend",
    runner = "xcode-27",
    test_targets = [
        ":NexusAgentTests",
        ":mirror_build_test",
    ],
    tier = "L1",
    timeout_minutes = 30,
)
