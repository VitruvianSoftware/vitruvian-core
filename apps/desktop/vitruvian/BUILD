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
#   :tool_protocol_pin_test
#                         the tool protocol's Swift sources match the pin in
#                         bazel/tool_protocol.sha256 (Linux-safe)
#   :source_lints_test    the rules over how the sources, build scripts and
#                         tests are written (Linux-safe)
#   :publish              builds the DMG and attaches it to a GitHub Release
#                         (the `vitruvian` delivery unit below)
#
# Swift has no Gazelle, so this file is hand-written. Everything that needs an
# Apple toolchain is `manual` + macOS-constrained so a Linux `bazel build //...`
# skips it; the macOS pipeline unit builds it by explicit label with
# --config=macos-app. See README.md for local usage.

load("@build_bazel_rules_apple//apple:macos.bzl", "macos_application", "macos_command_line_application", "macos_dylib")
load("@build_bazel_rules_apple//apple:resources.bzl", "apple_resource_group")
load("@build_bazel_rules_swift//swift:swift_binary.bzl", "swift_binary")
load("@build_bazel_rules_swift//swift:swift_interop_hint.bzl", "swift_interop_hint")
load("@build_bazel_rules_swift//swift:swift_library.bzl", "swift_library")
load("@build_bazel_rules_swift//swift:swift_test.bzl", "swift_test")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
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
        # The tool protocol's types (MIT, packages/vitruvian-sdk): the app and
        # a tool read each message from one definition. Core imports it by
        # name where it is used; it is not re-exported.
        "//packages/vitruvian-sdk:VitruvianToolProtocol",
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
        # The tool protocol's types, for the runtime under Services/Platform/
        # External that talks to a tool running as its own program.
        "//packages/vitruvian-sdk:VitruvianToolProtocol",
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
        # The tool protocol's types: the agreement sheet shows a tool's own
        # words, which its manifest file carries in several languages.
        "//packages/vitruvian-sdk:VitruvianToolProtocol",
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

# A tool the unit tests start as a real child process: it speaks the tool
# protocol and has a command for each way a tool can behave, well or badly
# (Tools/ToolFixture.swift lists them). A script like MakeIcon, so it is
# compiled as main.swift the same way. It links nothing of the app.
genrule(
    name = "tool_fixture_main",
    srcs = ["Tools/ToolFixture.swift"],
    outs = ["tool_fixture_src/main.swift"],
    cmd = "cp $< $@",
)

swift_binary(
    name = "tool_fixture",
    srcs = [":tool_fixture_main"],
    copts = [
        "-default-isolation",
        "MainActor",
    ],
    features = ["swift.enable_v6"],
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
)

# Looks at, and presses, the controls of the running Vitruvian app from the
# shell, through the macOS Accessibility API: how the checks by hand of the
# tools from outside are done. AGENTS.md says how to use it.
#   bazel run --config=macos-app //apps/desktop/vitruvian:by-hand -- <command>
# A development tool. Nothing depends on it, so it is in no bundle and no
# release; the pipeline unit below builds it, so it cannot stop compiling
# unnoticed, and no test runs it: it drives the app that is running. It links
# nothing of the app. A script like MakeIcon, so its first file is compiled as
# main.swift the same way; Tools/ByHandRules.swift holds the choices it makes
# before it presses anything, and the unit tests compile that file too.
genrule(
    name = "by_hand_main",
    srcs = ["Tools/ByHand.swift"],
    outs = ["by_hand_src/main.swift"],
    cmd = "cp $< $@",
)

swift_binary(
    name = "by-hand",
    srcs = [
        "Tools/ByHandRules.swift",
        ":by_hand_main",
    ],
    copts = [
        "-default-isolation",
        "MainActor",
    ],
    features = ["swift.enable_v6"],
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
)

# Checks against the live internet what the unit tests check against
# fixtures: the app's own update check finds the newest release and its
# universal disk image, and every link on Settings > About opens. With
# `-- --verify-download` it also checks that image the way the installer does.
# By hand only: no test depends on the network.
#   bazel run --config=macos-app //apps/desktop/vitruvian:release_feed_check
genrule(
    name = "release_feed_check_main",
    srcs = ["Tools/ReleaseFeedCheck.swift"],
    outs = ["release_feed_check_src/main.swift"],
    cmd = "cp $< $@",
)

swift_binary(
    name = "release_feed_check",
    package_name = SWIFT_PACKAGE,
    srcs = [":release_feed_check_main"],
    copts = [
        "-default-isolation",
        "MainActor",
    ],
    features = ["swift.enable_v6"],
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
    deps = [
        ":VitruvianCore",
        ":VitruvianServices",
    ],
)

rust_library(
    name = "make_icons_lib",
    srcs = ["bazel/src/make_icons/lib.rs"],
    crate_name = "make_icons",
    edition = "2021",
)

rust_binary(
    name = "make_icons_tool",
    srcs = ["bazel/src/make_icons/main.rs"],
    edition = "2021",
    deps = [":make_icons_lib"],
)

rust_test(
    name = "make_icons_test",
    size = "small",
    crate = ":make_icons_lib",
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
    cmd = "$(location :make_icons_tool) $(location :make_icon) " + package_name() + "/Resources/Brand $(RULEDIR)/icons",
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
    tools = [
        ":make_icon",
        ":make_icons_tool",
    ],
)

rust_library(
    name = "helper_version_plist_lib",
    srcs = ["bazel/src/helper_version_plist/lib.rs"],
    crate_name = "helper_version_plist",
    edition = "2021",
)

rust_binary(
    name = "helper_version_plist_tool",
    srcs = ["bazel/src/helper_version_plist/main.rs"],
    edition = "2021",
    deps = [":helper_version_plist_lib"],
)

rust_test(
    name = "helper_version_plist_test",
    size = "small",
    crate = ":helper_version_plist_lib",
)

genrule(
    name = "fan_helper_version_plist",
    srcs = [
        ":" + FAN_HELPER_ID,
        "Resources/com.vitruviansoftware.vitruvian.fan-control.plist",
    ],
    outs = ["fan_helper_version/Info.plist"],
    cmd = "$(execpath :helper_version_plist_tool) $(location :" + FAN_HELPER_ID + ") $(location Resources/com.vitruviansoftware.vitruvian.fan-control.plist) $@",
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
    tools = [":helper_version_plist_tool"],
)

rust_library(
    name = "bundle_info_plist_lib",
    srcs = ["bazel/src/bundle_info_plist/lib.rs"],
    crate_name = "bundle_info_plist",
    edition = "2021",
)

rust_binary(
    name = "bundle_info_plist_tool",
    srcs = ["bazel/src/bundle_info_plist/main.rs"],
    edition = "2021",
    deps = [":bundle_info_plist_lib"],
)

rust_test(
    name = "bundle_info_plist_test",
    size = "small",
    crate = ":bundle_info_plist_lib",
    data = ["Resources/Info.plist"],
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
        # GitHub tool from the catalog finds here for its status light.
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

rust_library(
    name = "sync_sources_lib",
    srcs = ["bazel/src/sync_sources/lib.rs"],
    crate_name = "sync_sources",
    edition = "2021",
    deps = [":generate_sources_lib"],
)

rust_binary(
    name = "sync_sources",
    srcs = ["bazel/src/sync_sources/main.rs"],
    edition = "2021",
    deps = [":sync_sources_lib"],
)

rust_test(
    name = "sync_sources_test",
    size = "small",
    crate = ":sync_sources_lib",
    data = [
        "bazel/sources.bzl",
        "build.sh",
    ] + glob([
        "Sources/**/*.swift",
    ]),
)

rust_library(
    name = "mutation_checks_lib",
    srcs = [
        "bazel/src/mutation_checks/lib.rs",
        "bazel/src/mutation_checks/mutations.rs",
    ],
    crate_name = "mutation_checks",
    edition = "2021",
)

# Upstream's mutation checks: each listed regression must fail the
# test meant to catch it. It edits the checkout in place and drives
# `bazel test` itself, so it is run rather than tested, on macOS:
#   bazel run --config=macos-app //apps/desktop/vitruvian:mutation_checks
# .github/workflows/vitruvian-mutation-checks.yaml runs it weekly.
rust_binary(
    name = "mutation_checks",
    srcs = ["bazel/src/mutation_checks/main.rs"],
    edition = "2021",
    deps = [":mutation_checks_lib"],
)

rust_test(
    name = "mutation_checks_test",
    size = "small",
    crate = ":mutation_checks_lib",
)

# The same file, reading only: every mutation still quotes its source exactly.
# A change that moves or rewords a quoted line fails here, in its own pull
# request, instead of stopping the weekly run. Not `manual` and not macOS-only,
# so it also runs wherever `bazel test //...` does. A few mutations are planted
# in the tool protocol's sources, hence that package's files in `data`.
rust_test(
    name = "mutation_fixtures_test",
    size = "small",
    srcs = ["bazel/src/mutation_checks/fixtures_test.rs"],
    data = [
        "Resources/Info.plist",
        "//packages/vitruvian-sdk:protocol_sources",
    ] + glob([
        "Sources/**/*.swift",
        "Tests/**/*.swift",
    ]),
    edition = "2021",
    deps = [":mutation_checks_lib"],
)

rust_library(
    name = "generate_sources_lib",
    srcs = ["bazel/src/generate_sources/lib.rs"],
    crate_name = "generate_sources",
    edition = "2021",
)

rust_binary(
    name = "generate_sources",
    srcs = ["bazel/src/generate_sources/main.rs"],
    edition = "2021",
    deps = [":generate_sources_lib"],
)

rust_test(
    name = "generate_sources_test",
    size = "small",
    crate = ":generate_sources_lib",
    data = glob([
        "Sources/**/*.swift",
    ]),
)

rust_library(
    name = "make_placeholder_brand_lib",
    srcs = ["bazel/src/make_placeholder_brand/lib.rs"],
    crate_name = "make_placeholder_brand",
    edition = "2021",
)

rust_binary(
    name = "make_placeholder_brand",
    srcs = ["bazel/src/make_placeholder_brand/main.rs"],
    edition = "2021",
    deps = [":make_placeholder_brand_lib"],
)

rust_test(
    name = "make_placeholder_brand_test",
    size = "small",
    crate = ":make_placeholder_brand_lib",
    data = glob(["Resources/Brand/**"]),
)

rust_library(
    name = "preference_cleanup_tests_lib",
    srcs = ["bazel/src/preference_cleanup_tests/lib.rs"],
    crate_name = "preference_cleanup_tests",
    edition = "2021",
)

rust_binary(
    name = "preference_cleanup_tests",
    srcs = ["bazel/src/preference_cleanup_tests/main.rs"],
    edition = "2021",
    deps = [":preference_cleanup_tests_lib"],
)

rust_test(
    name = "preference_cleanup_tests_test",
    size = "small",
    crate = ":preference_cleanup_tests_lib",
)

rust_library(
    name = "uninstall_spaces_tests_lib",
    srcs = ["bazel/src/uninstall_spaces_tests/lib.rs"],
    crate_name = "uninstall_spaces_tests",
    edition = "2021",
)

rust_binary(
    name = "uninstall_spaces_tests",
    srcs = ["bazel/src/uninstall_spaces_tests/main.rs"],
    edition = "2021",
    deps = [":uninstall_spaces_tests_lib"],
)

rust_test(
    name = "uninstall_spaces_tests_test",
    size = "small",
    crate = ":uninstall_spaces_tests_lib",
)

# Emits generated test sources (see sync_sources).
genrule(
    name = "generated_test_sources",
    srcs = [
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
    ) + glob(["Tests/*.swift"]) + glob(["Tests/SwiftTesting/*.swift"]) + [
        # What the by-hand command decides before it presses anything.
        "Tools/ByHandRules.swift",
        ":generated_test_sources",
    ],
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
        # ExternalToolManifestTests names the manifest file's own types.
        "//packages/vitruvian-sdk:VitruvianToolProtocol",
    ],
)

rust_library(
    name = "run_unit_tests_lib",
    srcs = ["bazel/src/run_unit_tests/lib.rs"],
    crate_name = "run_unit_tests",
    edition = "2021",
    deps = [
        ":preference_cleanup_tests_lib",
        ":uninstall_spaces_tests_lib",
    ],
)

rust_test(
    name = "run_unit_tests_test",
    size = "small",
    crate = ":run_unit_tests_lib",
)

rust_test(
    name = "unit_tests",
    size = "large",
    srcs = ["bazel/src/run_unit_tests/main.rs"],
    args = [
        "$(rootpath :unit_tests_bin)",
        package_name(),
    ],
    data = [
        "build.sh",
        ":tool_fixture",
        ":unit_tests_bin",
        "//packages/vitruvian-sdk:folder_examples",
        "//packages/vitruvian-sdk:message_examples",
    ] + glob([
        "Resources/**",
        "Sources/**",
        "Tests/**",
        "Tools/**",
    ]),
    edition = "2021",
    # Where ToolProcessTests finds the tool it starts, where
    # ToolFolderExamplesTests finds the folders the SDK's command-line tool is
    # held to as well, and where ExternalToolSettingsTests finds the protocol's
    # example messages, below the runfiles.
    env = {
        "VITRUVIAN_FOLDER_EXAMPLES": "$(rootpath //packages/vitruvian-sdk:folder_examples)",
        "VITRUVIAN_MESSAGE_EXAMPLES": "$(rootpath //packages/vitruvian-sdk:message_examples)",
        "VITRUVIAN_TOOL_FIXTURE": "$(rootpath :tool_fixture)",
    },
    # The tests' UserDefaults suites land in the real ~/Library/Preferences;
    # the sandbox would block sweeping them afterwards.
    tags = [
        "manual",
        "no-remote",
        "no-sandbox",
    ],
    target_compatible_with = MACOS_ONLY,
    use_libtest_harness = False,
    deps = [":run_unit_tests_lib"],
)

rust_library(
    name = "run_selftest_lib",
    srcs = ["bazel/src/run_selftest/lib.rs"],
    crate_name = "run_selftest",
    edition = "2021",
)

rust_test(
    name = "run_selftest_test",
    size = "small",
    crate = ":run_selftest_lib",
)

rust_test(
    name = "selftest",
    size = "medium",
    srcs = ["bazel/src/run_selftest/main.rs"],
    args = [
        "Vitruvian",
        "$(rootpaths :Vitruvian)",
    ],
    data = [":Vitruvian"],
    edition = "2021",
    tags = [
        "manual",
        "no-remote",
        "no-sandbox",
    ],
    target_compatible_with = MACOS_ONLY,
    use_libtest_harness = False,
    deps = [":run_selftest_lib"],
)

rust_library(
    name = "run_binary_lib",
    srcs = ["bazel/src/run_binary/lib.rs"],
    crate_name = "run_binary",
    edition = "2021",
)

rust_test(
    name = "run_binary_test",
    size = "small",
    crate = ":run_binary_lib",
)

rust_test(
    name = "fan_helper_selftest",
    size = "small",
    srcs = ["bazel/src/run_binary/main.rs"],
    args = [
        "$(rootpath :" + FAN_HELPER_ID + ")",
        "--selftest",
    ],
    data = [":" + FAN_HELPER_ID],
    edition = "2021",
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
    use_libtest_harness = False,
    deps = [":run_binary_lib"],
)

test_suite(
    name = "sources_in_sync_test",
    tests = [":sync_sources_test"],
)

# The same guard for the tool protocol's Swift sources (packages/vitruvian-sdk),
# which VitruvianCore links. It does two jobs. A change to them must also
# change this folder, or this app would never release it. And it is the only
# test here that depends on them and is not `manual`, so it is the only one
# the presubmit planner lists for a change made only in the package. It is in
# this app's pipeline unit, so the planner then selects the unit and the
# app's tests run (checked 2026-10-10).
TOOL_PROTOCOL = ["//packages/vitruvian-sdk:protocol_sources"]

TOOL_PROTOCOL_ARGS = [
    "--name",
    "tool_protocol",
] + ["$(rootpaths %s)" % group for group in TOOL_PROTOCOL]

rust_library(
    name = "pin_nexus_agent_shared_lib",
    srcs = ["bazel/src/pin_nexus_agent_shared/lib.rs"],
    crate_name = "pin_nexus_agent_shared",
    edition = "2021",
)

rust_binary(
    name = "pin_tool_protocol",
    srcs = ["bazel/src/pin_nexus_agent_shared/main.rs"],
    args = TOOL_PROTOCOL_ARGS,
    data = TOOL_PROTOCOL,
    edition = "2021",
    deps = [":pin_nexus_agent_shared_lib"],
)

rust_test(
    name = "pin_nexus_agent_shared_test",
    size = "small",
    crate = ":pin_nexus_agent_shared_lib",
    data = ["bazel/tool_protocol.sha256"] + TOOL_PROTOCOL,
    env = {
        "TOOL_PROTOCOL_PIN_FILE": "$(rootpath bazel/tool_protocol.sha256)",
        "TOOL_PROTOCOL_SOURCES": " ".join(["$(rootpaths %s)" % group for group in TOOL_PROTOCOL]),
    },
)

test_suite(
    name = "tool_protocol_pin_test",
    tests = [":pin_nexus_agent_shared_test"],
)

rust_library(
    name = "dmg_image_devices_lib",
    srcs = ["bazel/src/dmg_image_devices/lib.rs"],
    crate_name = "dmg_image_devices",
    edition = "2021",
)

rust_binary(
    name = "dmg_image_devices",
    srcs = ["bazel/src/dmg_image_devices/main.rs"],
    edition = "2021",
    deps = [":dmg_image_devices_lib"],
)

# make-dmg.sh finds a disk image's attachments in what `hdiutil info` prints.
# Held to the output a macOS runner printed when a failed create left an image
# attached that the script could not find.
rust_test(
    name = "dmg_image_devices_test",
    size = "small",
    crate = ":dmg_image_devices_lib",
    data = ["bazel/testdata/hdiutil-info-stale-image.txt"],
)

rust_library(
    name = "beta_publish_guard_lib",
    srcs = ["bazel/src/beta_publish_guard/lib.rs"],
    crate_name = "beta_publish_guard",
    edition = "2021",
)

rust_binary(
    name = "beta_publish_guard",
    srcs = ["bazel/src/beta_publish_guard/main.rs"],
    edition = "2021",
    deps = [":beta_publish_guard_lib"],
)

# Whether a beta publish goes ahead, skips (a newer build is already on the
# release) or refuses, from how its commit relates to the rolling tag's.
rust_test(
    name = "beta_publish_guard_test",
    size = "small",
    crate = ":beta_publish_guard_lib",
)

rust_library(
    name = "build_app_lib",
    srcs = ["bazel/src/build_app/lib.rs"],
    crate_name = "build_app",
    edition = "2021",
)

rust_binary(
    name = "build_app",
    srcs = ["bazel/src/build_app/main.rs"],
    edition = "2021",
    deps = [":build_app_lib"],
)

rust_test(
    name = "build_app_test",
    size = "small",
    crate = ":build_app_lib",
)

rust_library(
    name = "publish_lib",
    srcs = ["bazel/src/publish/lib.rs"],
    crate_name = "publish",
    edition = "2021",
)

rust_binary(
    name = "publish_rs",
    srcs = ["bazel/src/publish/main.rs"],
    edition = "2021",
    deps = [":publish_lib"],
)

rust_test(
    name = "publish_test",
    size = "small",
    crate = ":publish_lib",
)

rust_library(
    name = "uninstall_lib",
    srcs = ["bazel/src/uninstall/lib.rs"],
    crate_name = "uninstall",
    edition = "2021",
)

rust_binary(
    name = "uninstall",
    srcs = ["bazel/src/uninstall/main.rs"],
    edition = "2021",
    deps = [":uninstall_lib"],
)

rust_test(
    name = "uninstall_test",
    size = "small",
    crate = ":uninstall_lib",
)

rust_library(
    name = "make_dmg_lib",
    srcs = ["bazel/src/make_dmg/lib.rs"],
    crate_name = "make_dmg",
    edition = "2021",
)

rust_binary(
    name = "make_dmg",
    srcs = ["bazel/src/make_dmg/main.rs"],
    edition = "2021",
    deps = [":make_dmg_lib"],
)

rust_test(
    name = "make_dmg_test",
    size = "small",
    crate = ":make_dmg_lib",
)

rust_library(
    name = "package_release_lib",
    srcs = ["bazel/src/package_release/lib.rs"],
    crate_name = "package_release",
    edition = "2021",
)

rust_binary(
    name = "package_release",
    srcs = ["bazel/src/package_release/main.rs"],
    edition = "2021",
    deps = [":package_release_lib"],
)

rust_test(
    name = "package_release_test",
    size = "small",
    crate = ":package_release_lib",
)

rust_library(
    name = "setup_signing_lib",
    srcs = ["bazel/src/setup_signing/lib.rs"],
    crate_name = "setup_signing",
    edition = "2021",
)

rust_binary(
    name = "setup_signing",
    srcs = ["bazel/src/setup_signing/main.rs"],
    edition = "2021",
    deps = [":setup_signing_lib"],
)

rust_test(
    name = "setup_signing_test",
    size = "small",
    crate = ":setup_signing_lib",
)

rust_library(
    name = "notarize_lib",
    srcs = ["bazel/src/notarize/lib.rs"],
    crate_name = "notarize",
    edition = "2021",
)

rust_binary(
    name = "notarize",
    srcs = ["bazel/src/notarize/main.rs"],
    edition = "2021",
    deps = [":notarize_lib"],
)

rust_test(
    name = "notarize_test",
    size = "small",
    crate = ":notarize_lib",
)

rust_library(
    name = "ci_setup_signing_lib",
    srcs = ["bazel/src/ci_setup_signing/lib.rs"],
    crate_name = "ci_setup_signing",
    edition = "2021",
)

rust_binary(
    name = "ci_setup_signing",
    srcs = ["bazel/src/ci_setup_signing/main.rs"],
    edition = "2021",
    deps = [":ci_setup_signing_lib"],
)

rust_test(
    name = "ci_setup_signing_test",
    size = "small",
    crate = ":ci_setup_signing_lib",
)

rust_library(
    name = "source_lints_lib",
    srcs = ["bazel/src/source_lints/lib.rs"],
    crate_name = "source_lints",
    edition = "2021",
)

rust_binary(
    name = "source_lints",
    srcs = ["bazel/src/source_lints/main.rs"],
    edition = "2021",
    deps = [":source_lints_lib"],
)

# Rules over how all of the code is written, not what one piece of it does: an
# API that never appears, every SF Symbol and system tool named, the build
# script's temp-dir sweep, and the rest. They read the sources as text, so they
# run here rather than in the unit tests.
rust_test(
    name = "source_lints_test",
    size = "small",
    crate = ":source_lints_lib",
    data = [
        "Tools/beta-publish-guard.sh",
        "Tools/dmg-image-devices.sh",
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
)

# --- Upstream tracking ---------------------------------------------------------
# UPSTREAM.md, "Tracking and porting upstream":
#   bazel run //apps/desktop/vitruvian:track_upstream -- status|triage|show|port
# .github/workflows/vitruvian-upstream-watch.yaml runs `status` daily.

rust_library(
    name = "upstream_lib",
    srcs = ["upstream/src/lib.rs"],
    crate_name = "vitruvian_upstream_rs",
    edition = "2021",
)

rust_binary(
    name = "track_upstream",
    srcs = ["upstream/src/main.rs"],
    edition = "2021",
    deps = [":upstream_lib"],
)

rust_test(
    name = "upstream_test",
    size = "small",
    crate = ":upstream_lib",
    data = ["upstream/ledger.tsv"],
    env = {"UPSTREAM_LEDGER": "$(rootpath upstream/ledger.tsv)"},
)

# --- Pipeline -----------------------------------------------------------------

pipeline_unit(
    name = "vitruvian-desktop-macos",
    # Services builds with complete concurrency checking, REFACTOR.md 6zu,
    # and each of its compile actions writes more than Bazel's default 1 MB of
    # warnings, which Bazel then skips printing. Show all of it, so the log
    # lists what still stands between Services and Swift 6 mode.
    build_flags = ["--experimental_ui_max_stdouterr_bytes=-1"],
    persona = "frontend",
    runner = "xcode-27",
    test_targets = [
        ":Vitruvian",
        ":VitruvianLibWithSampleTool",
        ":by-hand",
        ":fan_helper_selftest",
        ":mutation_fixtures_test",
        ":selftest",
        ":source_lints_test",
        ":sources_in_sync_test",
        ":tool_protocol_pin_test",
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

# The catalog's public key, as the app is built with it. //catalog:catalog_test
# holds it equal to catalog/public-key.txt.
exports_files(
    ["Sources/Vitruvian/Services/Platform/External/Catalogue/CatalogueSigning.swift"],
    visibility = ["//catalog:__pkg__"],
)

# The oldest macOS the app runs on (LSMinimumSystemVersion). //catalog:bump
# refuses a tool whose programs need a newer one.
exports_files(
    ["Resources/Info.plist"],
    visibility = ["//catalog:__pkg__"],
)

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
