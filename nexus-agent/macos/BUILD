load("@build_bazel_rules_apple//apple:macos.bzl", "macos_application")
load("@build_bazel_rules_swift//swift:swift_library.bzl", "swift_library")

# NexusAgent is a dependency-free SwiftUI/AppKit menu-bar agent (LSUIElement).
# Swift has no Gazelle, so this BUILD file is hand-written. The library is
# constrained to macOS so a Linux `bazel build //...` skips it instead of
# failing to find an Apple toolchain.
swift_library(
    name = "NexusAgent_lib",
    srcs = glob(["Sources/NexusAgent/**/*.swift"]),
    module_name = "NexusAgent",
    target_compatible_with = ["@platforms//os:macos"],
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
    visibility = ["//visibility:public"],
    deps = [":NexusAgent_lib"],
)
