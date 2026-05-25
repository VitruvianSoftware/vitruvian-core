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
    visibility = ["//visibility:public"],
    deps = [":NexusAgent_lib"],
)
