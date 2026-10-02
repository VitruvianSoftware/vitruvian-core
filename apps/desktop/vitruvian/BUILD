# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

# Bazel build of the imported menu-bar utility app (upstream: vorssaint-utils,
# see UPSTREAM.md). It reproduces upstream's build.sh:
#
#   :Vorssaint            the .app: app binary, privileged fan helper, Now Playing
#                         adapter dylib, launchd plist, icons and resources
#   :unit_tests           upstream's unit-test binary (`build.sh --test`)
#   :selftest             the assembled app's `--selftest` health check
#   :fan_helper_selftest  the fan helper's own `--selftest`
#   :sources_in_sync_test bazel/sources.bzl still matches build.sh (Linux-safe)
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
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
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

# Bundle identity. Upstream's trademark policy (TRADEMARKS.md) forbids
# distributing a modified build under these; the rename to Vitruvian replaces
# them. Until then nothing built here is published -- CI builds and tests only.
BUNDLE_ID = "com.vorssaint.utils"

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

# --- The app ------------------------------------------------------------------

# One module, as upstream builds it. main.swift holds top-level code, which
# rules_swift allows by not passing -parse-as-library when a main.swift is
# present.
swift_library(
    name = "VorssaintLib",
    srcs = glob(["Sources/Vorssaint/**/*.swift"]),
    module_name = "Vorssaint",
    target_compatible_with = MACOS_ONLY,
    deps = [
        ":HIDEventSystem",
        ":VMStatisticsCompat",
    ],
)

# The privileged fan-control helper, registered as a launchd daemon from
# Contents/Library/LaunchServices. Its file name must be the helper's label.
swift_library(
    name = "FanControlHelperLib",
    srcs = FAN_HELPER_SOURCES,
    module_name = "FanControlHelper",
    target_compatible_with = MACOS_ONLY,
)

macos_command_line_application(
    name = FAN_HELPER_ID,
    bundle_id = FAN_HELPER_ID,
    minimum_os_version = "14.0",
    tags = ["manual"],
    deps = [":FanControlHelperLib"],
)

# Now Playing is read by /usr/bin/perl (Resources/now-playing.pl) loading this
# library from Contents/Frameworks.
swift_library(
    name = "VorssaintNowPlayingLib",
    srcs = NOW_PLAYING_SOURCES,
    module_name = "VorssaintNowPlaying",
    target_compatible_with = MACOS_ONLY,
)

macos_dylib(
    name = "libVorssaintNowPlaying",
    bundle_id = BUNDLE_ID + ".now-playing",
    infoplists = ["bazel/NowPlayingAdapter-Info.plist"],
    minimum_os_version = "14.0",
    tags = ["manual"],
    deps = [":VorssaintNowPlayingLib"],
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
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
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
        "Resources/com.vorssaint.utils.fan-control.plist",
    ],
    outs = ["fan_helper_version/Info.plist"],
    cmd = "$(location bazel/helper_version_plist.sh) $(location :" + FAN_HELPER_ID + ") $(location Resources/com.vorssaint.utils.fan-control.plist) $@",
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
    name = "Vorssaint",
    additional_contents = {
        ":" + FAN_HELPER_ID: "Library/LaunchServices",
        "Resources/com.vorssaint.utils.fan-control.plist": "Library/LaunchDaemons",
        ":libVorssaintNowPlaying": "Frameworks",
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
    deps = [":VorssaintLib"],
)

# --- Tests --------------------------------------------------------------------

py_binary(
    name = "sync_sources",
    srcs = ["bazel/sync_sources.py"],
    main = "bazel/sync_sources.py",
)

# Runs the unmodified upstream Tests/generate_sources.py (see sync_sources.py).
genrule(
    name = "generated_test_sources",
    srcs = [
        "Tests/generate_sources.py",
        "build.sh",
    ] + glob([
        "Sources/**/*.swift",
        "Tests/Fixtures/**",
    ]),
    outs = ["generated-tests/" + f for f in GENERATED_TEST_SOURCES],
    cmd = "$(execpath :sync_sources) --app-dir " + package_name() + " --emit-generated $(RULEDIR)/generated-tests",
    tools = [":sync_sources"],
)

# Upstream's test binary: the listed production sources, Tests/*.swift and the
# generated extractions compiled as one module with its own @main runner.
swift_binary(
    name = "unit_tests_bin",
    srcs = glob(TEST_PRODUCTION_SOURCES) + glob(["Tests/*.swift"]) + [":generated_test_sources"],
    module_name = "VorssaintTests",
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
    deps = [":VMStatisticsCompat"],
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
        "Vorssaint",
        "$(rootpaths :Vorssaint)",
    ],
    data = [":Vorssaint"],
    tags = [
        "manual",
        "no-remote",
        "no-sandbox",
    ],
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
        "Tests/Fixtures/**",
    ]),
    main = "bazel/sync_sources.py",
)

# --- Pipeline -----------------------------------------------------------------

pipeline_unit(
    name = "vitruvian-desktop-macos",
    persona = "frontend",
    runner = "xcode-27",
    test_targets = [
        ":Vorssaint",
        ":fan_helper_selftest",
        ":selftest",
        ":sources_in_sync_test",
        ":unit_tests",
    ],
    tier = "L1",
    timeout_minutes = 60,
)
