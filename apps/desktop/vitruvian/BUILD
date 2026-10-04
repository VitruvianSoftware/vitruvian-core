# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

# Bazel build of the imported menu-bar utility app (upstream: vorssaint-utils,
# see UPSTREAM.md). It reproduces upstream's build.sh:
#
#   :Vitruvian            the .app: app binary, privileged fan helper, Now Playing
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
    deps = [":FanControlKit"],
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

# Everything not yet in a module of its own. main.swift holds top-level code,
# which rules_swift allows by not passing -parse-as-library when a main.swift
# is present.
swift_library(
    name = "VitruvianLib",
    package_name = SWIFT_PACKAGE,
    srcs = glob(
        ["Sources/Vitruvian/**/*.swift"],
        exclude = CORE_SRCS + DESIGN_SRCS + SERVICES_SRCS + UI_SRCS + FAN_CONTROL_KIT_SRCS,
    ),
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
        "Tests/Fixtures/**",
    ]),
    outs = ["generated-tests/" + f for f in GENERATED_TEST_SOURCES],
    cmd = "$(execpath :sync_sources) --app-dir " + package_name() + " --emit-generated $(RULEDIR)/generated-tests",
    tools = [":sync_sources"],
)

# Upstream's test binary: the listed production sources, Tests/*.swift and the
# generated extractions compiled as one module with its own @main runner.
# Listed sources that now live in a module come from that module instead; today
# that is all of them, so the first glob is empty until upstream lists a file
# outside the modules again.
swift_binary(
    name = "unit_tests_bin",
    package_name = SWIFT_PACKAGE,
    srcs = glob(
        TEST_PRODUCTION_SOURCES,
        allow_empty = True,
        exclude = CORE_SRCS + DESIGN_SRCS + SERVICES_SRCS + UI_SRCS + FAN_CONTROL_KIT_SRCS,
    ) + glob(["Tests/*.swift"]) + [":generated_test_sources"],
    # PROBE (reverted before merge): Swift 6 mode, one frontend per file.
    copts = ["-continue-building-after-errors"],
    features = [
        "swift.enable_v6",
        "-swift.enable_batch_mode",
    ],
    module_name = "VitruvianTests",
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
    deps = [
        ":FanControlKit",
        ":VMStatisticsCompat",
        ":VitruvianCore",
        ":VitruvianDesign",
        ":VitruvianServices",
        ":VitruvianUI",
    ],
)

# PROBE (reverted before merge): lists the closures Swift 6 mode guards with a
# run-time main-thread check, each a call to swift_task_reportUnexpectedExecutor.
genrule(
    name = "tests_executor_checks",
    srcs = [":unit_tests_bin"],
    outs = ["tests_executor_checks.txt"],
    cmd = """
for f in $(SRCS); do
  case "$$f" in
    *unit_tests_bin) xcrun objdump -dr --no-show-raw-insn "$$f" ;;
  esac
done | awk '/^[0-9a-f]+ <.*>:$$/ { fn = $$2 } /swift_task_reportUnexpectedExecutor/ { print fn }' \\
  | sort -u | tr -d '<>:' | sed 's/^_\\$$/$$/' | xcrun swift-demangle \\
  | grep -E '(^| )VitruvianTests[.]' > $@ || true
echo "PROBE executor checks: $$(wc -l < $@)" >&2
cat $@ >&2
""",
    local = True,
    tags = ["manual"],
    target_compatible_with = MACOS_ONLY,
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
        # PROBE (reverted before merge): builds the list above.
        ":tests_executor_checks",
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
    # Services builds with complete concurrency checking (REFACTOR.md 6zu),
    # and each of its compile actions writes more than Bazel's default 1 MB of
    # warnings, which Bazel then skips printing. Show all of it, so the log
    # lists what still stands between Services and Swift 6 mode.
    build_flags = ["--experimental_ui_max_stdouterr_bytes=-1"],
    persona = "frontend",
    runner = "xcode-27",
    test_targets = [
        ":Vitruvian",
        ":fan_helper_selftest",
        ":selftest",
        ":sources_in_sync_test",
        ":unit_tests",
    ],
    tier = "L1",
    timeout_minutes = 60,
)
