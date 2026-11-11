load("@build_bazel_rules_apple//apple:macos.bzl", "macos_application")
load("@build_bazel_rules_swift//swift:swift_library.bzl", "swift_library")
load("//tools/pipeline:defs.bzl", "pipeline_unit")
load("//tools/swift-test-preferences:defs.bzl", "swift_test")

# The bridge: the last release of Nexus Agent. Old installs update themselves by
# swapping in the NexusAgent.app inside the release's "universal" zip; that app
# is this one, and all it does is install Vitruvian Code and go to the Trash
# (docs/superpowers/specs/2026-11-10-vitruvian-code-rename-design.md).
# It uses nothing of the app's modules, and nothing outside the system.
# MUST MIRROR Package.swift: SwiftPM builds it for the release.

# What decides things, apart from the window, so the tests run it with a
# downloader that never touches the network.
swift_library(
    name = "BridgeCore",
    srcs = glob(["Sources/BridgeCore/*.swift"]),
    module_name = "BridgeCore",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
)

swift_test(
    name = "BridgeTests",
    size = "small",
    srcs = glob(["Tests/BridgeCoreTests/*.swift"]),
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":BridgeCore"],
)

# bazel build --config=macos-app //apps/desktop/vitruvian-code/bridge:NexusAgent
# Not in wildcard builds, as the app bundle is not (see macos/BUILD).
macos_application(
    name = "NexusAgent",
    bundle_id = "com.vitruviansoftware.nexusagent",
    bundle_name = "NexusAgent",
    infoplists = ["Resources/Info.plist"],
    minimum_os_version = "14.0",
    tags = ["manual"],
    visibility = ["//apps/desktop/vitruvian-code:__subpackages__"],
    deps = [":NexusAgentLib"],
)

swift_library(
    name = "NexusAgentLib",
    srcs = glob(["Sources/NexusAgentBridge/*.swift"]),
    module_name = "NexusAgent",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":BridgeCore"],
)

pipeline_unit(
    name = "vitruvian-code-bridge",
    depends_on = ["vitruvian-code-src"],
    persona = "frontend",
    runner = "xcode-27",
    test_targets = [":BridgeTests"],
    tier = "L1",
    timeout_minutes = 20,
)
