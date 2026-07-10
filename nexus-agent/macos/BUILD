load("@build_bazel_rules_apple//apple:macos.bzl", "macos_application")
load("@build_bazel_rules_swift//swift:swift_library.bzl", "swift_library")
load("@build_bazel_rules_swift//swift:swift_test.bzl", "swift_test")

# Pure, UI-free logic (version parse/compare) in its own module so the test binary
# can link it WITHOUT the app's `@main` (App.swift), which would otherwise collide
# with XCTest's own `main` ("duplicate symbol _main") (#807).
swift_library(
    name = "NexusAgentCore",
    srcs = glob(["Sources/NexusAgentCore/**/*.swift"]),
    module_name = "NexusAgentCore",
    target_compatible_with = ["@platforms//os:macos"],
)

# NexusAgent is a dependency-free SwiftUI/AppKit menu-bar agent (LSUIElement).
# Swift has no Gazelle, so this BUILD file is hand-written. The library is
# constrained to macOS so a Linux `bazel build //...` skips it instead of
# failing to find an Apple toolchain.
swift_library(
    name = "NexusAgent_lib",
    srcs = glob(["Sources/NexusAgent/**/*.swift"]),
    module_name = "NexusAgent",
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":NexusAgentCore"],
)

# Unit tests for the pure-logic pieces. Depends on NexusAgentCore only (NOT the
# app lib), so no `@main` is linked in. macOS-only + `manual` like the app bundle,
# so a Linux `bazel build/test //...` skips it; the macОС CI leg runs it by
# explicit label (#807).
swift_test(
    name = "NexusAgent_tests",
    srcs = glob(["Tests/**/*.swift"]),
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":NexusAgentCore"],
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
    # visibility; nothing outside //nexus-agent may dep the bundle.
    visibility = ["//nexus-agent:__subpackages__"],
    deps = [":NexusAgent_lib"],
)
