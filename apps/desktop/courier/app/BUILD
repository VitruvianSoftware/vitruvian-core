# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-or-later

# //apps/desktop/courier/app: Courier.app, which runs and supervises the
# courier-engine helper (../engine/cmd/courier-engine) and talks to it over the
# protocol in ../protocol.
#
# Swift has no Gazelle, so this file is hand-written. It MUST MIRROR
# Package.swift, target for target.

load("@build_bazel_rules_apple//apple:macos.bzl", "macos_application")
load("@build_bazel_rules_apple//apple:versioning.bzl", "apple_bundle_version")
load("@build_bazel_rules_swift//swift:swift_library.bzl", "swift_library")
load("@build_bazel_rules_swift//swift:swift_test.bzl", "swift_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("//tools/pipeline:defs.bzl", "pipeline_unit")
load(":version.bzl", "COURIER_VERSION")

# Everything the tests need: the protocol's types, the engine client, the
# supervisor, the Keychain and the app's model. The app target has `@main`, and
# linking that into a test gives a duplicate `_main` symbol, so the code lives
# here.
swift_library(
    name = "CourierCore",
    srcs = glob(["Sources/CourierCore/**/*.swift"]),
    module_name = "CourierCore",
    target_compatible_with = ["@platforms//os:macos"],
)

swift_library(
    name = "CourierLib",
    srcs = glob(["Sources/Courier/**/*.swift"]),
    module_name = "Courier",
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":CourierCore"],
)

# The app's views without App.swift (whose @main no test can link), as the module Courier, compiled for
# @testable import: CourierViewTests renders them. Test-only; the app itself is CourierLib.
swift_library(
    name = "CourierViews",
    testonly = True,
    srcs = glob(
        ["Sources/Courier/**/*.swift"],
        exclude = ["Sources/Courier/App.swift"],
    ),
    features = ["swift.enable_testing"],
    module_name = "Courier",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":CourierCore"],
)

# ProtocolConformanceTests reads the protocol's definition and examples, the
# same files the engine's Go tests check, and RichTextTests the formatting
# cases the engine's richtext tests render. The client and supervisor tests run a
# stand-in engine on a Unix socket under /tmp and a fake launcher: nothing here
# starts the real engine. macOS-only and `manual`, like the other Mac apps'
# tests: the courier-app-macos unit below runs it by label. Medium, not small: on
# the CI Mac runner the whole suite takes about a minute, past small's 60 s.
swift_test(
    name = "CourierCoreTests",
    size = "medium",
    srcs = glob(["Tests/CourierCoreTests/**/*.swift"]),
    data = [
        "//apps/desktop/courier/protocol",
        "//apps/desktop/courier/protocol:richtext_cases",
    ] + glob(["Sources/**/*.swift"]),
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":CourierCore"],
)

# A render harness, not a test of how anything looks: it draws the views (message bubbles, the poll, the thread
# summary, the composer with its formatting bar, the pickers, the scheduled strip, Settings ▸ Messages), light and
# dark, to PNGs in the test's undeclared outputs (bazel-testlogs/.../CourierViewTests/test.outputs), and asserts only
# that each drew at a sensible size. A person reads the PNGs before a view change ships: green tests have shipped a
# broken layout before. SwiftPM's CourierViewTests is the same harness against the executable target.
swift_test(
    name = "CourierViewTests",
    size = "small",
    srcs = glob(["Tests/CourierViewTests/**/*.swift"]),
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":CourierCore",
        ":CourierViews",
    ],
)

# CFBundleShortVersionString and CFBundleVersion: the engine's go_binary stamps
# the same COURIER_VERSION, so the two never differ.
apple_bundle_version(
    name = "version",
    build_version = COURIER_VERSION,
    short_version_string = COURIER_VERSION,
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
)

# The engine, as the file the app bundles. macos_application's
# additional_contents keeps a file's path relative to its package, and rules_go
# writes a go_binary to `<name>_/<name>`, so the go_binary given directly lands
# at Contents/Helpers/courier-engine_/courier-engine. This copy is the same
# binary at `courier-engine` in this package, so it lands at
# Contents/Helpers/courier-engine. It is built in the app's configuration (the
# darwin platform macos_application transitions to): arm64 only until
# milestone 6's universal build.
genrule(
    name = "engine_helper",
    srcs = ["//apps/desktop/courier/engine/cmd/courier-engine"],
    outs = ["courier-engine"],
    cmd = "cp $(location //apps/desktop/courier/engine/cmd/courier-engine) $@ && chmod 755 $@",
    executable = True,
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
)

# bazel build --config=macos-app //apps/desktop/courier/app:Courier
#
# The engine goes in Contents/Helpers, where the app looks for it
# (EngineLocation.swift).
#
# `manual`: macos_application transitions to a darwin platform, so
# target_compatible_with cannot keep it out of a Linux `//...`. AppIcon.icns is
# a loose resource (no asset catalog; see scripts/make-icon.swift). Ad-hoc
# signed.
macos_application(
    name = "Courier",
    additional_contents = {
        ":engine_helper": "Helpers",
    },
    bundle_id = "com.vitruviansoftware.courier",
    infoplists = ["Resources/Info.plist"],
    minimum_os_version = "14.0",
    resources = ["Resources/AppIcon.icns"] + glob(["Resources/*.lproj/*.strings"]),
    tags = ["manual"],
    version = ":version",
    visibility = ["//apps/desktop/courier:__subpackages__"],
    deps = [":CourierLib"],
)

# The app Bazel built holds a working engine: Contents/Helpers/courier-engine
# is an arm64 executable that answers --help with its usage, and the bundle's
# version is COURIER_VERSION. It reads the archive :Courier already produced.
rust_test(
    name = "app_holds_engine_test",
    size = "small",
    srcs = ["scripts/src/bin/app_holds_engine.rs"],
    args = [
        COURIER_VERSION,
        "$(rootpaths :Courier)",
    ],
    crate_root = "scripts/src/bin/app_holds_engine.rs",
    data = [":Courier"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    use_libtest_harness = False,
    deps = [":courier_scripts_lib"],
)

# bazel run --config=macos-app //apps/desktop/courier/app:install [-- --dest DIR]
#
# Puts the app Bazel built into /Applications (or DIR) with Courier's own Telegram app ID added.
# It builds nothing but its data (Courier.zip). The app ID never passes through a Bazel action,
# whose outputs can land in the remote cache: :inject-app-credentials adds it to the
# unpacked app afterwards, on this Mac, from the environment or the gitignored secret store
# (tools/sync-env-secrets), and signs the app again: the engine, then the app, with the Developer ID
# if one is installed (and the hardened runtime) and Resources/Courier.entitlements. See README.md.
sh_binary(
    name = "install",
    srcs = ["scripts/install.sh"],
    args = [
        "$(rootpath :inject-app-credentials)",
        "$(rootpaths :Courier)",
    ],
    data = [
        "Resources/Courier.entitlements",
        ":Courier",
        ":inject-app-credentials",
    ],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
)

# The injector against a tiny stand-in app: it writes a valid TelegramApp.plist, signs the app so
# it passes codesign --verify, refuses bad values without printing them, and honours
# --allow-missing. A fake codesign proves how it signs (the engine before the app, the identifier,
# the hardened runtime and timestamp only with an identity, the entitlements). macOS-only (plutil, codesign) and `manual`: the courier-app-macos unit below
# runs it by label.
rust_test(
    name = "inject_app_credentials_test",
    size = "small",
    crate = ":courier_scripts_lib",
    data = ["Resources/Courier.entitlements"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
)

# What the app assumes about its engine (the flags it starts it with, the
# protocol number), checked against the engine and protocol.json. Not
# `manual` and not tied to macOS: it is the only test here that the presubmit
# planner lists for a change made only in the engine or the protocol (it skips
# manual tests), so it is what makes the planner select the unit below then.
rust_test(
    name = "engine_contract_test",
    size = "small",
    srcs = ["scripts/src/bin/engine_contract.rs"],
    args = [
        "$(rootpath //apps/desktop/courier/engine/cmd/courier-engine)",
        "$(rootpath Sources/CourierCore/EngineSupervisor.swift)",
        "$(rootpath Sources/CourierCore/Protocol.swift)",
        "$(rootpaths //apps/desktop/courier/protocol)",
    ],
    crate_root = "scripts/src/bin/engine_contract.rs",
    data = [
        "Sources/CourierCore/EngineSupervisor.swift",
        "Sources/CourierCore/Protocol.swift",
        "//apps/desktop/courier/engine/cmd/courier-engine",
        "//apps/desktop/courier/protocol",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    use_libtest_harness = False,
    deps = [":courier_scripts_lib"],
)

pipeline_unit(
    name = "courier-app-macos",
    persona = "frontend",
    runner = "xcode-27",
    test_targets = [
        ":CourierCoreTests",
        ":CourierViewTests",
        ":app_holds_engine_test",
        ":engine_contract_test",
        ":inject_app_credentials_test",
    ],
    tier = "L1",
    # A cold build of the engine it bundles is libsignal's 2,000+ actions
    # (../engine/BUILD); the remote cache makes later runs much shorter.
    timeout_minutes = 60,
)

# --- Rust ports of courier app scripts ----------------------------------------

rust_library(
    name = "courier_scripts_lib",
    srcs = glob(
        ["scripts/src/**/*.rs"],
        exclude = ["scripts/src/bin/*.rs"],
    ),
    crate_name = "courier_scripts_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_test(
    name = "courier_scripts_lib_test",
    size = "small",
    crate = ":courier_scripts_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "inject-app-credentials",
    srcs = ["scripts/src/bin/inject_app_credentials.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/desktop/courier:__subpackages__"],
    deps = [":courier_scripts_lib"],
)

alias(
    name = "inject_app_credentials",
    actual = ":inject-app-credentials",
    visibility = ["//apps/desktop/courier:__subpackages__"],
)

rust_binary(
    name = "engine-contract",
    srcs = ["scripts/src/bin/engine_contract.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/desktop/courier:__subpackages__"],
    deps = [":courier_scripts_lib"],
)

alias(
    name = "engine_contract",
    actual = ":engine-contract",
    visibility = ["//apps/desktop/courier:__subpackages__"],
)

rust_binary(
    name = "app-holds-engine",
    srcs = ["scripts/src/bin/app_holds_engine.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/desktop/courier:__subpackages__"],
    deps = [":courier_scripts_lib"],
)

alias(
    name = "app_holds_engine",
    actual = ":app-holds-engine",
    visibility = ["//apps/desktop/courier:__subpackages__"],
)

rust_binary(
    name = "install-rs",
    srcs = ["scripts/src/bin/install.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/desktop/courier:__subpackages__"],
    deps = [":courier_scripts_lib"],
)

alias(
    name = "install_rs",
    actual = ":install-rs",
    visibility = ["//apps/desktop/courier:__subpackages__"],
)

test_suite(
    name = "engine_contract_rs_test",
    tests = [":engine_contract_test"],
)

test_suite(
    name = "app_holds_engine_rs_test",
    tags = ["manual"],
    tests = [":app_holds_engine_test"],
)

test_suite(
    name = "inject_app_credentials_rs_test",
    tags = ["manual"],
    tests = [":inject_app_credentials_test"],
)
