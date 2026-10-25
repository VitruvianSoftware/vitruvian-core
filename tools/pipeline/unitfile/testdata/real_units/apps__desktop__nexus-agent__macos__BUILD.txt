load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@build_bazel_rules_apple//apple:macos.bzl", "macos_application")
load("@build_bazel_rules_swift//swift:swift_binary.bzl", "swift_binary")
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

# The Nexus Agent tool for the Vitruvian app (docs/superpowers/plans/2026-10-12-vitruvian-tools-for-everyone-stage-f.md):
# what it knows, apart from the link to the app. The settings host over
# settings.json, the two pages, the words in fifteen languages, and the
# state machine behind a link protocol, so the tests drive it without a
# process. Swift 6 mode, as the core. It links the MIT kit and protocol
# (packages/vitruvian-sdk) and the shared libraries, and nothing of the
# Vitruvian app.
swift_library(
    name = "NexusAgentToolCore",
    srcs = glob(["Sources/NexusAgentToolCore/**/*.swift"]),
    features = ["swift.enable_v6"],
    module_name = "NexusAgentToolCore",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":NexusAgentCore",
        "//packages/vitruvian-sdk:VitruvianToolKit",
        "//packages/vitruvian-sdk:VitruvianToolProtocol",
    ],
)

# Against an engine over files held in memory, a link that records and a
# window that records. Nothing here starts a process or reaches the home
# folder.
swift_test(
    name = "NexusAgentToolTests",
    size = "small",
    srcs = glob(["Tests/NexusAgentToolTests/**/*.swift"]),
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":NexusAgentCore",
        ":NexusAgentToolCore",
        "//packages/vitruvian-sdk:VitruvianToolKit",
        "//packages/vitruvian-sdk:VitruvianToolProtocol",
    ],
)

# The tool's program: AppKit on the main thread for the Quick Prompt's
# window, the kit's loop on a thread of its own, and NexusAgentToolCore
# between them; nothing else.
swift_binary(
    name = "nexus-agent-tool",
    srcs = glob(["Sources/NexusAgentTool/*.swift"]),
    features = ["swift.enable_v6"],
    module_name = "NexusAgentToolProgram",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":NexusAgentCore",
        ":NexusAgentToolCore",
        ":NexusAgentUI",
        "//packages/vitruvian-sdk:VitruvianToolKit",
        "//packages/vitruvian-sdk:VitruvianToolProtocol",
    ],
)

# The tool as a folder the app can add: the manifest, bin/tool, and the
# copy of Mermaid the chat's diagram cards draw with beside the program,
# where NexusAgentMermaidPage looks for an executable that is no bundle.
# The mirror's release zips the same three.
#
#   bazel build --config=macos-app //apps/desktop/nexus-agent/macos:tool-folder
#
# leaves bazel-bin/apps/desktop/nexus-agent/macos/built/nexus-agent/.
genrule(
    name = "tool-folder",
    srcs = [
        "tool/vitruvian-tool.json",
        "Sources/NexusAgentUI/Resources/mermaid.min.js",
        ":nexus-agent-tool",
    ],
    outs = [
        "built/nexus-agent/vitruvian-tool.json",
        "built/nexus-agent/bin/tool",
        "built/nexus-agent/bin/mermaid.min.js",
    ],
    cmd = "cp $(location tool/vitruvian-tool.json) $(RULEDIR)/built/nexus-agent/vitruvian-tool.json && cp $(location :nexus-agent-tool) $(RULEDIR)/built/nexus-agent/bin/tool && cp $(location Sources/NexusAgentUI/Resources/mermaid.min.js) $(RULEDIR)/built/nexus-agent/bin/mermaid.min.js",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
)

# The built folder through `vitruvian-tool validate` and the conformance
# script, under a home of its own: the handshake, a command, an unknown
# command, the island panel opened and tapped, refusals, and a clean exit.
# It starts the real program.
py_test(
    name = "tool_conformance_test",
    size = "medium",
    srcs = ["tool/conformance_test.py"],
    args = [
        "$(rootpath built/nexus-agent/vitruvian-tool.json)",
        "$(rootpath //packages/vitruvian-sdk:conformance/conformance.py)",
        "$(rootpath //packages/vitruvian-sdk:vitruvian-tool)",
    ],
    data = [
        "built/nexus-agent/vitruvian-tool.json",
        ":tool-folder",
        "//packages/vitruvian-sdk:conformance/conformance.py",
        "//packages/vitruvian-sdk:vitruvian-tool",
    ],
    main = "tool/conformance_test.py",
    tags = [
        "block-network",
        "manual",
    ],
    target_compatible_with = ["@platforms//os:macos"],
)

# The tool's version is the app's, in the manifest, the tool's Version.swift
# and the app's; and release-please writes all three. Not tied to macOS.
py_test(
    name = "tool_version_test",
    size = "small",
    srcs = ["tool/version_test.py"],
    data = [
        "Package.swift",
        "Sources/NexusAgent/Version.swift",
        "Sources/NexusAgentToolCore/Version.swift",
        "tool/vitruvian-tool.json",
        "//apps/desktop/nexus-agent:release_please_config",
    ],
    main = "tool/version_test.py",
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
    # The tool's tests are a target of their own, below: they link the
    # tool's core, which this target does not.
    srcs = glob(
        ["Tests/**/*.swift"],
        exclude = ["Tests/NexusAgentToolTests/**"],
    ),
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

# The app Bazel built holds the copy of Mermaid the chat view ships
# (scripts/bazel_app_holds_mermaid_test.sh says why nothing else would notice).
# It reads the archive `:NexusAgent` already produced, so it costs no build
# where the app is built: the macos-build job of .github/workflows/ci.yaml,
# which runs it by label. It is deliberately not in the unit below, which does
# not build the app and would have to.
sh_test(
    name = "app_holds_mermaid_test",
    size = "small",
    srcs = ["scripts/bazel_app_holds_mermaid_test.sh"],
    args = [
        "NexusAgent",
        "$(rootpaths :NexusAgent)",
        "$(rootpaths :shared_ui_resources)",
    ],
    data = [
        ":NexusAgent",
        ":shared_ui_resources",
    ],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
)

# The Vitruvian desktop app runs the same check on its own archive.
exports_files(
    ["scripts/bazel_app_holds_mermaid_test.sh"],
    visibility = ["//apps/desktop/vitruvian:__pkg__"],
)

pipeline_unit(
    name = "nexus-agent-macos",
    depends_on = ["nexus-agent-src"],
    persona = "frontend",
    runner = "xcode-27",
    test_targets = [
        ":NexusAgentTests",
        ":NexusAgentToolTests",
        ":mirror_build_test",
        ":nexus-agent-tool",
        ":tool_conformance_test",
        ":tool_version_test",
    ],
    tier = "L1",
    timeout_minutes = 30,
)
