# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

# Bazel build of the imported menu-bar utility app (upstream: vorssaint-utils,
# see UPSTREAM.md). It reproduces upstream's build.sh:
#
#   :Vitruvian            the .app: app binary, privileged fan helper, Now Playing
#                         adapter dylib, launchd plist, icons and resources
#   :unit_tests           the unit tests, which Swift Testing runs
#   :selftest             the assembled app's `--selftest` health check
#   :fan_helper_selftest  the fan helper's own `--selftest`
#   :sources_in_sync_test bazel/sources.bzl still matches build.sh (Linux-safe)
#   :nexus_agent_shared_pin_test
#                         the shared Nexus Agent sources match the pin in
#                         bazel/nexus_agent_shared.sha256 (Linux-safe)
#   :source_lints_test    the rules over how the sources, build scripts and
#                         tests are written (Linux-safe)
#   :publish              builds the DMG and attaches it to a GitHub Release
#                         (the `vitruvian` delivery unit below)
#
# Swift has no Gazelle, so this file is hand-written. Everything that needs an
# Apple toolchain is `manual` + macOS-constrained so a Linux `bazel build //...`
# skips it; the macOS pipeline unit builds it by explicit label with
# --config=macos-app. See README.md for local usage.

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_test")
load("@build_bazel_rules_apple//apple:macos.bzl", "macos_application", "macos_command_line_application", "macos_dylib")
load("@build_bazel_rules_apple//apple:resources.bzl", "apple_resource_group")
load("@build_bazel_rules_swift//swift:swift_binary.bzl", "swift_binary")
load("@build_bazel_rules_swift//swift:swift_interop_hint.bzl", "swift_interop_hint")
load("@build_bazel_rules_swift//swift:swift_library.bzl", "swift_library")
load("@build_bazel_rules_swift//swift:swift_test.bzl", "swift_test")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//tools/delivery:defs.bzl", "delivery")
load("//tools/pipeline:defs.bzl", "pipeline_unit")
load(
    ":bazel/sources.bzl",
    "FAN_HELPER_SOURCES",
    "GENERATED_TEST_SOURCES",
    "NOW_PLAYING_SOURCES",
    "TEST_PRODUCTION_SOURCES",
)

# gazelle:ignore

# Inter-app boundary (#82): nothing outside this app may depend on its internals.
package(default_visibility = ["//visibility:private"])

MACOS_ONLY = ["@platforms//os:macos"]

# Bundle identity: Vitruvian's own, never upstream's (TRADEMARKS.md). Nothing
# built here is published yet -- CI builds and tests only; see UPSTREAM.md for
# what has to exist before a first release.
BUNDLE_ID = "com.vitruviansoftware.vitruvian"

FAN_HELPER_ID = BUNDLE_ID + ".fan-control"

# --- C modules imported from Swift -------------------------------------------
# upstream passes `-I Sources/<module>` so swiftc finds each module.modulemap;
# here the same module maps are attached to header-only cc_library targets.

swift_interop_hint(
    name = "HIDEventSystem_interop",
    module_map = "Sources/HIDEventSystem/module.modulemap",
    module_name = "HIDEventSystem",
)

cc_library(
    name = "HIDEventSystem",
    hdrs = glob(["Sources/HIDEventSystem/include/*.h"]),
    aspect_hints = [":HIDEventSystem_interop"],
    target_compatible_with = MACOS_ONLY,
)

swift_interop_hint(
    name = "VMStatisticsCompat_interop",
    module_map = "Sources/VMStatisticsCompat/module.modulemap",
    module_name = "VMStatisticsCompat",
)

cc_library(
    name = "VMStatisticsCompat",
    hdrs = glob(["Sources/VMStatisticsCompat/include/*.h"]),
    aspect_hints = [":VMStatisticsCompat_interop"],
    target_compatible_with = MACOS_ONLY,
)

# --- Modules ------------------------------------------------------------------
# REFACTOR.md step 3. Every target shares one Swift package name, so `package`
# declarations are visible across them and nowhere else.

SWIFT_PACKAGE = "Vitruvian"

# Core/ is the VitruvianCore module, the whole folder: preferences keys,
# localization and pure helpers. Bazel enforces its direction: it depends on no
# other app module, so it can never reach a service, a view or the app
# lifecycle. A file that needs one belongs under Services/ or UI/ instead.
CORE_SRCS = glob(["Sources/Vitruvian/Core/**/*.swift"])

swift_library(
    name = "VitruvianCore",
    package_name = SWIFT_PACKAGE,
    srcs = CORE_SRCS,
    # Swift 6 language mode: complete concurrency checking, so shared state
    # says what protects it (REFACTOR.md step 6a).
    features = ["swift.enable_v6"],
    module_name = "VitruvianCore",
    target_compatible_with = MACOS_ONLY,
    deps = [
        ":FanControlKit",
        "//apps/desktop/nexus-agent/macos:NexusAgentCore",
    ],
)

# Design/ is the VitruvianDesign module: the AppKit and SwiftUI building blocks
# (panels, backdrops, editors) that services and views share. It knows no
# feature and depends on Core alone.
DESIGN_SRCS = glob(["Sources/Vitruvian/Design/**/*.swift"])

swift_library(
    name = "VitruvianDesign",
    package_name = SWIFT_PACKAGE,
    srcs = DESIGN_SRCS,
    # Swift 6 language mode, as VitruvianCore.
    features = ["swift.enable_v6"],
    module_name = "VitruvianDesign",
    target_compatible_with = MACOS_ONLY,
    deps = [":VitruvianCore"],
)

# Services/ is the VitruvianServices module: the singletons that own live system
# state (audio, displays, windows, the notch, captures) and the work behind each
# feature. It depends on Core and Design, never on a view or the app lifecycle;
# a service shows SwiftUI content through ServiceViews and reaches the app shell
# through AppShell.
SERVICES_SRCS = glob(["Sources/Vitruvian/Services/**/*.swift"])

swift_library(
    name = "VitruvianServices",
    package_name = SWIFT_PACKAGE,
    srcs = SERVICES_SRCS,
    # Swift 6 language mode since REFACTOR.md step 6zzi: complete concurrency
    # checking as errors, and main-actor closures checked at run time. Step
    # 6zzh moved the callbacks that run off the main thread out of the main
    # actor.
    features = ["swift.enable_v6"],
    module_name = "VitruvianServices",
    target_compatible_with = MACOS_ONLY,
    deps = [
        ":FanControlKit",
        ":HIDEventSystem",
        ":VMStatisticsCompat",
        ":VitruvianCore",
        ":VitruvianDesign",
    ],
)

# UI/ is the VitruvianUI module: the SwiftUI views and the windows that host
# them. It depends on Core, Design and Services, never on the app lifecycle;
# it reaches the running app through AppShell.
UI_SRCS = glob(["Sources/Vitruvian/UI/**/*.swift"])

swift_library(
    name = "VitruvianUI",
    package_name = SWIFT_PACKAGE,
    srcs = UI_SRCS,
    # Swift 6 language mode since REFACTOR.md step 6e: complete concurrency
    # checking as errors, and main-actor code checked at run time.
    features = ["swift.enable_v6"],
    module_name = "VitruvianUI",
    target_compatible_with = MACOS_ONLY,
    deps = [
        ":VitruvianCore",
        ":VitruvianDesign",
        ":VitruvianServices",
        # The Nexus Agent chat view, shared with the standalone app. Only this
        # module may depend on it: it is SwiftUI, and the layers below are not
        # all views.
        "//apps/desktop/nexus-agent/macos:NexusAgentUI",
    ],
)

# Fan-control policy and the SMC temperature model, shared by the app (through
# VitruvianCore, which re-exports it) and the privileged fan helper. A module of
# its own so the helper links this and nothing else of the app.
FAN_CONTROL_KIT_SRCS = glob(["Sources/Vitruvian/FanControlKit/*.swift"])

swift_library(
    name = "FanControlKit",
    package_name = SWIFT_PACKAGE,
    srcs = FAN_CONTROL_KIT_SRCS,
    # Swift 6 language mode since REFACTOR.md step 6zzk.
    features = ["swift.enable_v6"],
    module_name = "FanControlKit",
    target_compatible_with = MACOS_ONLY,
)

# --- The app ------------------------------------------------------------------

# A development build that registers the sample tool (Services/Platform/
# SampleTool.swift), a tool outside every fixed list, so the surfaces can be
# checked by hand:  --define=vitruvian_sample_tool=true
config_setting(
    name = "sample_tool",
    define_values = {"vitruvian_sample_tool": "true"},
)

# Everything not yet in a module of its own. main.swift holds top-level code,
# which rules_swift allows by not passing -parse-as-library when a main.swift
# is present.
APP_SRCS = glob(
    ["Sources/Vitruvian/**/*.swift"],
    exclude = CORE_SRCS + DESIGN_SRCS + SERVICES_SRCS + UI_SRCS + FAN_CONTROL_KIT_SRCS,
)

swift_library(
    name = "VitruvianLib",
    package_name = SWIFT_PACKAGE,
    srcs = APP_SRCS,
    copts = select({
        ":sample_tool": ["-DVITRUVIAN_SAMPLE_TOOL"],
        "//conditions:default": [],
    }),
    # Swift 6 language mode since REFACTOR.md step 6zzj. Each of its closures
    # that checks for the main thread at run time runs there.
    features = ["swift.enable_v6"],
    module_name = "Vitruvian",
    target_compatible_with = MACOS_ONLY,
    deps = [
        ":FanControlKit",
        ":HIDEventSystem",
        ":VMStatisticsCompat",
        ":VitruvianCore",
        ":VitruvianDesign",
        ":VitruvianServices",
        ":VitruvianUI",
    ],
)

# The same module, compiled as a build with the sample tool would compile it.
# Nothing links it. It is built in CI (the pipeline unit below lists it), so
# the lines of main.swift that only a --define=vitruvian_sample_tool=true
# build compiles cannot stop compiling without anybody noticing.
swift_library(
    name = "VitruvianLibWithSampleTool",
    package_name = SWIFT_PACKAGE,
    srcs = APP_SRCS,
    copts = ["-DVITRUVIAN_SAMPLE_TOOL"],
    features = ["swift.enable_v6"],
    module_name = "Vitruvian",
    target_compatible_with = MACOS_ONLY,
    deps = [
        ":FanControlKit",
        ":HIDEventSystem",
        ":VMStatisticsCompat",
        ":VitruvianCore",
        ":VitruvianDesign",
        ":VitruvianServices",
        ":VitruvianUI",
    ],
)

# The privileged fan-control helper, registered as a launchd daemon from
# Contents/Library/LaunchServices. Its file name must be the helper's label.
# build.sh compiles FanControlKit's files into the helper; here they come from
# that module, and the helper's uses of its `package` API need the package name.
swift_library(
    name = "FanControlHelperLib",
    package_name = SWIFT_PACKAGE,
    srcs = [src for src in FAN_HELPER_SOURCES if src not in FAN_CONTROL_KIT_SRCS],
    # Swift 6 language mode since REFACTOR.md step 6zzk. The closures that check
    # for the main thread at run time are the signal handlers, which run there.
    features = ["swift.enable_v6"],
    module_name = "FanControlHelper",
    target_compatible_with = MACOS_ONLY,
    deps = [":FanControlKit"],
)

macos_command_line_application(
    name = FAN_HELPER_ID,
    bundle_id = FAN_HELPER_ID,
    minimum_os_version = "14.0",
    tags = ["manual"],
    deps = [":FanControlHelperLib"],
)

# Now Playing is read by /usr/bin/perl (Resources/now-playing.pl) loading this
# library from Contents/Frameworks. Two of its files are VitruvianServices
# sources too, whose `package` declarations need the package name.
swift_library(
    name = "VitruvianNowPlayingLib",
    package_name = SWIFT_PACKAGE,
    srcs = NOW_PLAYING_SOURCES,
    # Swift 6 language mode since REFACTOR.md step 6zzl.
    features = ["swift.enable_v6"],
    module_name = "VitruvianNowPlaying",
    target_compatible_with = MACOS_ONLY,
)

macos_dylib(
    name = "libVitruvianNowPlaying",
    bundle_id = BUNDLE_ID + ".now-playing",
    infoplists = ["bazel/NowPlayingAdapter-Info.plist"],
    minimum_os_version = "14.0",
    tags = ["manual"],
    deps = [":VitruvianNowPlayingLib"],
)

# Tools/MakeIcon.swift is a script (top-level code). rules_swift compiles a
# single non-main.swift source with -parse-as-library, so compile it as main.swift.
genrule(
    name = "make_icon_main",
    srcs = ["Tools/MakeIcon.swift"],
    outs = ["make_icon_src/main.swift"],
    cmd = "cp $< $@",
)

swift_binary(
    name = "make_icon",
    srcs = [":make_icon_main"],
    # Swift 6 language mode since REFACTOR.md step 6zzn. A script that runs on
    # the main thread: its top-level functions share the main actor with the
    # images they draw.
    copts = [
        "-default-isolation",
        "MainActor",
    ],
    features = ["swift.enable_v6"],
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
)

# Draws the Nexus Agent chat in fixed states and writes each as a PNG, to
# compare before and after a change that should not alter its look:
#   bazel run --config=macos-app //apps/desktop/vitruvian:nexus_agent_chat_snapshots -- <output folder>
# A script like MakeIcon, so it is compiled as main.swift the same way. It is
# in the app's Swift package because the view and the service are `package`.
genrule(
    name = "nexus_agent_chat_snapshots_main",
    srcs = ["Tools/NexusAgentChatSnapshots.swift"],
    outs = ["nexus_agent_chat_snapshots_src/main.swift"],
    cmd = "cp $< $@",
)

swift_binary(
    name = "nexus_agent_chat_snapshots",
    package_name = SWIFT_PACKAGE,
    srcs = [":nexus_agent_chat_snapshots_main"],
    copts = [
        "-default-isolation",
        "MainActor",
    ],
    features = ["swift.enable_v6"],
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
    deps = [
        ":VitruvianCore",
        ":VitruvianDesign",
        ":VitruvianServices",
        ":VitruvianUI",
        "//apps/desktop/nexus-agent/macos:NexusAgentUI",
    ],
)

# Shows the real Quick Prompt window for a few seconds and checks typing, Esc,
# ⌘W and a diagram in it, with a stand-in agent and files held in memory
# (Tools/NexusAgentWindowRun.swift says what is real and what stands in). A
# developer's tool that puts a window on the screen, so it is run by hand and
# is in no test or pipeline unit:
#   bazel run --config=macos-app //apps/desktop/vitruvian:nexus_agent_window_run -- [<Vitruvian.zip>]
# A script like the snapshot tool, compiled as main.swift the same way. It is
# an app and not a plain program because the chat finds its copy of Mermaid in
# the main bundle's resources, which is where rules_apple puts a library's
# `data` for an app and nowhere a plain program looks.
genrule(
    name = "nexus_agent_window_run_main",
    srcs = ["Tools/NexusAgentWindowRun.swift"],
    outs = ["nexus_agent_window_run_src/main.swift"],
    cmd = "cp $< $@",
)

swift_library(
    name = "nexus_agent_window_run_lib",
    package_name = SWIFT_PACKAGE,
    srcs = [":nexus_agent_window_run_main"],
    copts = [
        "-default-isolation",
        "MainActor",
    ],
    features = ["swift.enable_v6"],
    module_name = "NexusAgentWindowRun",
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
    deps = [
        ":VitruvianCore",
        ":VitruvianDesign",
        ":VitruvianServices",
        ":VitruvianUI",
        "//apps/desktop/nexus-agent/macos:NexusAgentUI",
    ],
)

# Its own bundle identifier, so its settings are never the app's.
macos_application(
    name = "nexus_agent_window_run",
    bundle_id = BUNDLE_ID + ".tools.nexus-agent-window-run",
    infoplists = ["Tools/NexusAgentWindowRun-Info.plist"],
    minimum_os_version = "14.0",
    tags = ["manual"],
    deps = [":nexus_agent_window_run_lib"],
)

genrule(
    name = "icons",
    srcs = glob(["Resources/Brand/*.png"]),
    outs = [
        "icons/AppIcon.icns",
        "icons/MenuBarIcon.png",
        "icons/MenuBarIcon@2x.png",
        "icons/BrandMark.png",
    ],
    cmd = "$(location bazel/make_icons.sh) $(location :make_icon) " + package_name() + "/Resources/Brand $(RULEDIR)/icons",
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
    tools = [
        "bazel/make_icons.sh",
        ":make_icon",
    ],
)

genrule(
    name = "fan_helper_version_plist",
    srcs = [
        ":" + FAN_HELPER_ID,
        "Resources/com.vitruviansoftware.vitruvian.fan-control.plist",
    ],
    outs = ["fan_helper_version/Info.plist"],
    cmd = "$(location bazel/helper_version_plist.sh) $(location :" + FAN_HELPER_ID + ") $(location Resources/com.vitruviansoftware.vitruvian.fan-control.plist) $@",
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
    tools = ["bazel/helper_version_plist.sh"],
)

py_binary(
    name = "bundle_info_plist_tool",
    srcs = ["bazel/bundle_info_plist.py"],
    main = "bazel/bundle_info_plist.py",
)

# Upstream's Info.plist with a version rules_apple accepts (see the script).
genrule(
    name = "bundle_info_plist",
    srcs = ["Resources/Info.plist"],
    outs = ["bundle/Info.plist"],
    cmd = "$(execpath :bundle_info_plist_tool) $< $@",
    tools = [":bundle_info_plist_tool"],
)

# Resources keep their folders (Contents/Resources/Gifs, Images); *.lproj
# folders are recognised by rules_apple on their own.
apple_resource_group(
    name = "structured_resources",
    strip_structured_resources_prefixes = ["Resources"],
    structured_resources = glob([
        "Resources/Gifs/*",
        "Resources/Images/*",
    ]),
)

macos_application(
    name = "Vitruvian",
    additional_contents = {
        ":" + FAN_HELPER_ID: "Library/LaunchServices",
        "Resources/com.vitruviansoftware.vitruvian.fan-control.plist": "Library/LaunchDaemons",
        ":libVitruvianNowPlaying": "Frameworks",
        # The GravaStar mouse command (MIT, packages/peripherals), which the
        # GitHub status light runs; GitHubMouseBinary.bundled finds it here.
        "//packages/peripherals:gravastar-mouse": "Helpers",
    },
    bundle_id = BUNDLE_ID,
    infoplists = [
        ":bundle_info_plist",
        ":fan_helper_version_plist",
    ],
    minimum_os_version = "14.0",
    resources = [
        "CHANGELOG.md",
        "Resources/agent-prices.json",
        "Resources/now-playing.pl",
        ":icons",
        ":structured_resources",
    ] + glob(["Resources/*.lproj/*.strings"]),
    tags = ["manual"],
    deps = [":VitruvianLib"],
)

# --- Tests --------------------------------------------------------------------

py_binary(
    name = "sync_sources",
    srcs = ["bazel/sync_sources.py"],
    main = "bazel/sync_sources.py",
)

# Upstream's Tests/mutation_checks.py: each listed regression must fail the
# test meant to catch it. It edits the checkout in place and drives
# `bazel test` itself, so it is run rather than tested, on macOS:
#   bazel run --config=macos-app //apps/desktop/vitruvian:mutation_checks
# .github/workflows/vitruvian-mutation-checks.yaml runs it weekly.
py_binary(
    name = "mutation_checks",
    srcs = ["Tests/mutation_checks.py"],
    main = "Tests/mutation_checks.py",
)

# Runs the unmodified upstream Tests/generate_sources.py (see sync_sources.py).
genrule(
    name = "generated_test_sources",
    srcs = [
        "Tests/generate_sources.py",
        "build.sh",
    ] + glob([
        "Sources/**/*.swift",
    ]),
    outs = ["generated-tests/" + f for f in GENERATED_TEST_SOURCES],
    cmd = "$(execpath :sync_sources) --app-dir " + package_name() + " --emit-generated $(RULEDIR)/generated-tests",
    tools = [":sync_sources"],
)

# The unit tests: the listed production sources, Tests/*.swift and the
# generated localization registry, compiled as one module that Swift Testing
# runs (REFACTOR.md step 7). Each suite in Tests/TestGroups.swift is one case,
# run on the main actor. Listed sources that now live in a module come from
# that module instead; today that is all of them, so the first glob is empty
# until upstream lists a file outside the modules again.
#
# Swift 6 language mode since REFACTOR.md step 6zzm. Every suite runs on the
# main thread, so the module defaults to the main actor; what runs on a queue
# or thread says `nonisolated`.
swift_test(
    name = "unit_tests_bin",
    package_name = SWIFT_PACKAGE,
    srcs = glob(
        TEST_PRODUCTION_SOURCES,
        allow_empty = True,
        exclude = CORE_SRCS + DESIGN_SRCS + SERVICES_SRCS + UI_SRCS + FAN_CONTROL_KIT_SRCS,
    ) + glob(["Tests/*.swift"]) + glob(["Tests/SwiftTesting/*.swift"]) + [":generated_test_sources"],
    copts = [
        "-default-isolation",
        "MainActor",
    ],
    features = ["swift.enable_v6"],
    module_name = "VitruvianTests",
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
    deps = [
        ":FanControlKit",
        ":VMStatisticsCompat",
        ":VitruvianCore",
        ":VitruvianDesign",
        ":VitruvianNowPlayingLib",
        ":VitruvianServices",
        ":VitruvianUI",
        # NexusAgentTests checks what the app hands the shared chat view.
        "//apps/desktop/nexus-agent/macos:NexusAgentUI",
    ],
)

sh_test(
    name = "unit_tests",
    size = "large",
    srcs = ["bazel/run_unit_tests.sh"],
    args = [
        "$(rootpath :unit_tests_bin)",
        package_name(),
    ],
    data = [
        "build.sh",
        ":unit_tests_bin",
    ] + glob([
        "Resources/**",
        "Sources/**",
        "Tests/**",
        "Tools/**",
    ]),
    # The tests' UserDefaults suites land in the real ~/Library/Preferences;
    # the sandbox would block sweeping them afterwards.
    tags = [
        "manual",
        "no-remote",
        "no-sandbox",
    ],
    target_compatible_with = MACOS_ONLY,
)

sh_test(
    name = "selftest",
    size = "medium",
    srcs = ["bazel/run_selftest.sh"],
    args = [
        "Vitruvian",
        "$(rootpaths :Vitruvian)",
    ],
    data = [":Vitruvian"],
    tags = [
        "manual",
        "no-remote",
        "no-sandbox",
    ],
    target_compatible_with = MACOS_ONLY,
)

# The app holds the copy of Mermaid the shared chat view ships: its diagram
# cards draw with it, and an app without it still builds, signs and opens. The
# script is the standalone Nexus Agent app's, run here on this app's archive,
# which `:Vitruvian` in the unit below has already built.
sh_test(
    name = "app_holds_mermaid_test",
    size = "small",
    srcs = ["//apps/desktop/nexus-agent/macos:scripts/bazel_app_holds_mermaid_test.sh"],
    args = [
        "Vitruvian",
        "$(rootpaths :Vitruvian)",
        "$(rootpaths //apps/desktop/nexus-agent/macos:shared_ui_resources)",
    ],
    data = [
        ":Vitruvian",
        "//apps/desktop/nexus-agent/macos:shared_ui_resources",
    ],
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
)

sh_test(
    name = "fan_helper_selftest",
    size = "small",
    srcs = ["bazel/run_binary.sh"],
    args = [
        "$(rootpath :" + FAN_HELPER_ID + ")",
        "--selftest",
    ],
    data = [":" + FAN_HELPER_ID],
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
)

py_test(
    name = "sources_in_sync_test",
    size = "small",
    srcs = ["bazel/sync_sources.py"],
    args = [
        "--check",
        "--app-dir",
        package_name(),
    ],
    data = [
        "Tests/generate_sources.py",
        "bazel/sources.bzl",
        "build.sh",
    ] + glob([
        "Sources/**/*.swift",
    ]),
    main = "bazel/sync_sources.py",
)

# Every change to the shared Nexus Agent sources must also change this folder,
# or this app would never release it (bazel/pin_nexus_agent_shared.py). Both
# shared libraries are pinned: the engine and the chat view, with the files the
# chat view ships beside its code (the copy of Mermaid that draws diagrams).
SHARED_NEXUS_AGENT = [
    "//apps/desktop/nexus-agent/macos:shared_sources",
    "//apps/desktop/nexus-agent/macos:shared_ui_resources",
    "//apps/desktop/nexus-agent/macos:shared_ui_sources",
]

SHARED_NEXUS_AGENT_PATHS = ["$(rootpaths %s)" % group for group in SHARED_NEXUS_AGENT]

py_binary(
    name = "pin_nexus_agent_shared",
    srcs = ["bazel/pin_nexus_agent_shared.py"],
    args = SHARED_NEXUS_AGENT_PATHS,
    data = SHARED_NEXUS_AGENT,
    main = "bazel/pin_nexus_agent_shared.py",
)

py_test(
    name = "nexus_agent_shared_pin_test",
    size = "small",
    srcs = ["bazel/pin_nexus_agent_shared.py"],
    args = [
        "--check",
        "$(rootpath bazel/nexus_agent_shared.sha256)",
    ] + SHARED_NEXUS_AGENT_PATHS,
    data = ["bazel/nexus_agent_shared.sha256"] + SHARED_NEXUS_AGENT,
    main = "bazel/pin_nexus_agent_shared.py",
)

# Rules over how all of the code is written, not what one piece of it does: an
# API that never appears, every SF Symbol and system tool named, the build
# script's temp-dir sweep, and the rest (bazel/source_lints.py). They read the
# sources as text, so they run here rather than in the unit tests.
py_test(
    name = "source_lints_test",
    size = "small",
    srcs = ["bazel/source_lints.py"],
    args = [
        "--app-dir",
        package_name(),
    ],
    data = [
        "Tools/make-dmg.sh",
        "Tools/notarize.sh",
        "Tools/package-release.sh",
        "Tools/uninstall.sh",
        "UPSTREAM.md",
        "build.sh",
        "publish.sh",
    ] + glob([
        "Resources/**",
        "Sources/**/*.swift",
        "Tests/**/*.swift",
    ]),
    main = "bazel/source_lints.py",
)

# --- Upstream tracking ---------------------------------------------------------
# UPSTREAM.md, "Tracking and porting upstream":
#   bazel run //apps/desktop/vitruvian:track_upstream -- status|triage|show|port
# .github/workflows/vitruvian-upstream-watch.yaml runs `status` daily.

py_binary(
    name = "track_upstream",
    srcs = ["upstream/upstream.py"],
    main = "upstream/upstream.py",
)

# The tool against throwaway repositories, and the committed ledger's format.
py_test(
    name = "upstream_test",
    size = "small",
    srcs = [
        "upstream/upstream.py",
        "upstream/upstream_test.py",
    ],
    data = ["upstream/ledger.tsv"],
    env = {"UPSTREAM_LEDGER": "$(rootpath upstream/ledger.tsv)"},
    main = "upstream/upstream_test.py",
)

# --- Pipeline -----------------------------------------------------------------

pipeline_unit(
    name = "vitruvian-desktop-macos",
    # Services builds with complete concurrency checking (REFACTOR.md 6zu),
    # and each of its compile actions writes more than Bazel's default 1 MB of
    # warnings, which Bazel then skips printing. Show all of it, so the log
    # lists what still stands between Services and Swift 6 mode.
    build_flags = ["--experimental_ui_max_stdouterr_bytes=-1"],
    persona = "frontend",
    runner = "xcode-27",
    test_targets = [
        ":Vitruvian",
        ":VitruvianLibWithSampleTool",
        ":app_holds_mermaid_test",
        ":fan_helper_selftest",
        ":selftest",
        ":source_lints_test",
        ":sources_in_sync_test",
        ":nexus_agent_shared_pin_test",
        ":unit_tests",
    ],
    tier = "L1",
    timeout_minutes = 60,
)

# Build + package + upload. The generated delivery workflow runs the script
# directly (bash apps/desktop/vitruvian/publish.sh); this binary is the
# break-glass path the README points at, and what the delivery() below names
# as `run`. macOS only, like everything that builds the app.
exports_files([
    "Tools/ci-setup-signing.sh",
    "publish.sh",
])

sh_binary(
    name = "publish",
    srcs = ["publish.sh"],
    tags = ["manual"],
)

# Delivery unit: the DMG release ladder.
#   beta        on every affected push to main -> rolling prerelease
#               vitruvian-beta-latest (Vitruvian-beta.dmg clobbered, tag moved
#               to HEAD);
#   production  on the release-please release vitruvian-vX.Y.Z ->
#               Vitruvian-X.Y.Z.dmg attached to that release.
# Declared here because this package owns the artifact. The release-please
# machinery that cuts the production tag lives in
# .github/workflows/vitruvian-release.yaml (release machinery, not delivery --
# the same split as iot-esp32-s3-release.yaml vs delivery-esp32-s3.yaml).
delivery(
    name = "vitruvian",
    app = "vitruvian",
    environments = [
        "beta",
        "production",
    ],
    # Path-only mode: this regex IS the unit's complete trigger set
    # (tools/ci/deploy-affected.sh step 2), so it names the whole package.
    # The app carries the GravaStar mouse command (Contents/Helpers), so a
    # change to packages/peripherals is a change to the app too.
    extra_paths = [
        "apps/desktop/vitruvian/",
        "packages/peripherals/",
    ],
    # No GitHub Environment: the publish binds none; it uploads with the run's
    # own GITHUB_TOKEN under a job-level contents: write.
    github_environment = "",
    kind = "publish",
    legacy_job = "package",
    legacy_workflow = ".github/workflows/vitruvian-release.yaml",
    promotion = "release:vitruvian-v",
    render = "transcribed",
    run = "//apps/desktop/vitruvian:publish",
)
