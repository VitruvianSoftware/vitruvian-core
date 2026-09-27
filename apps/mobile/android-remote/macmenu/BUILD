# //apps/mobile/android-remote/macmenu: the Vitruvian Remote menu bar app.
#
# A small SwiftUI MenuBarExtra (LSUIElement) that shows whether the Mac agent
# (../macagent) is up and whether a phone is linked, and does the few things
# that otherwise need a terminal: pair a phone, restart the agent, open its
# log, unpair every phone. It is its own app on purpose, separate from
# HomeSpeaker. It reads the agent's read-tier endpoints only and holds no
# token; pairing and unpairing run the agent's own CLI.
#
# Swift has no Gazelle, so this file is hand-written. The layout follows
# //apps/desktop/nexus-agent/macos: pure logic in RemoteMenuCore so the test
# links it without the app's @main.

load("@build_bazel_rules_apple//apple:macos.bzl", "macos_application")
load("@build_bazel_rules_swift//swift:swift_library.bzl", "swift_library")
load("@build_bazel_rules_swift//swift:swift_test.bzl", "swift_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
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
    srcs = glob(["Tests/**/*.swift"]),
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":RemoteMenuCore"],
)

# The menu finds the agent by the paths install.sh writes; fail when they drift.
sh_test(
    name = "paths_match_installer_test",
    size = "small",
    srcs = ["paths_match_installer_test.sh"],
    args = [
        "$(rootpath //apps/mobile/android-remote/macagent:install.sh)",
        "$(rootpath Sources/RemoteMenuCore/AgentStatus.swift)",
    ],
    data = [
        "Sources/RemoteMenuCore/AgentStatus.swift",
        "//apps/mobile/android-remote/macagent:install.sh",
    ],
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
sh_binary(
    name = "install",
    srcs = ["install.sh"],
    data = [":VitruvianRemote"],
    tags = ["manual"],
)

pipeline_unit(
    name = "remote-mac-menu",
    persona = "frontend",
    runner = "xcode-27",
    test_targets = [
        ":RemoteMenuTests",
        ":paths_match_installer_test",
    ],
    tier = "L1",
    timeout_minutes = 30,
)
