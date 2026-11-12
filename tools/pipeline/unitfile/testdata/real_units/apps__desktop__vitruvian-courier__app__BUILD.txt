# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-or-later

# //apps/desktop/vitruvian-courier/app: Vitruvian Courier.app, which runs and supervises the
# vitruvian-courier-engine helper (../engine/cmd/vitruvian-courier-engine) and talks to it over the
# protocol in ../protocol.
#
# Swift has no Gazelle, so this file is hand-written. It MUST MIRROR
# Package.swift, target for target.

load("@build_bazel_rules_apple//apple:apple.bzl", "apple_universal_binary")
load("@build_bazel_rules_apple//apple:macos.bzl", "macos_application")
load("@build_bazel_rules_apple//apple:versioning.bzl", "apple_bundle_version")
load("@build_bazel_rules_swift//swift:swift_library.bzl", "swift_library")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")
load("//tools/swift-test-preferences:defs.bzl", "swift_test")
load(":version.bzl", "VITRUVIAN_COURIER_VERSION")

# Everything the tests need: the protocol's types, the engine client, the
# supervisor, the Keychain and the app's model. The app target has `@main`, and
# linking that into a test gives a duplicate `_main` symbol, so the code lives
# here.
swift_library(
    name = "VitruvianCourierCore",
    srcs = glob(["Sources/VitruvianCourierCore/**/*.swift"]),
    module_name = "VitruvianCourierCore",
    target_compatible_with = ["@platforms//os:macos"],
)

swift_library(
    name = "VitruvianCourierLib",
    srcs = glob(["Sources/VitruvianCourier/**/*.swift"]),
    module_name = "VitruvianCourier",
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":VitruvianCourierCore"],
)

# The app's views without App.swift (whose @main no test can link), as the module VitruvianCourier, compiled for
# @testable import: VitruvianCourierViewTests renders them. Test-only; the app itself is VitruvianCourierLib.
swift_library(
    name = "VitruvianCourierViews",
    testonly = True,
    srcs = glob(
        ["Sources/VitruvianCourier/**/*.swift"],
        exclude = ["Sources/VitruvianCourier/App.swift"],
    ),
    features = ["swift.enable_testing"],
    module_name = "VitruvianCourier",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":VitruvianCourierCore"],
)

# ProtocolConformanceTests reads the protocol's definition and examples, the
# same files the engine's Go tests check, and RichTextTests the formatting
# cases the engine's richtext tests render. The client and supervisor tests run a
# stand-in engine on a Unix socket under /tmp and a fake launcher: nothing here
# starts the real engine. macOS-only and `manual`, like the other Mac apps'
# tests: the vitruvian-courier-app-macos unit below runs it by label. Medium, not small: on
# the CI Mac runner the whole suite takes about a minute, past small's 60 s.
swift_test(
    name = "VitruvianCourierCoreTests",
    size = "medium",
    srcs = glob(["Tests/VitruvianCourierCoreTests/**/*.swift"]),
    data = [
        "//apps/desktop/vitruvian-courier/engine/internal/gchat:gchat_test",
        "//apps/desktop/vitruvian-courier/protocol",
        "//apps/desktop/vitruvian-courier/protocol:logscrub_cases",
        "//apps/desktop/vitruvian-courier/protocol:richtext_cases",
    ] + glob(["Sources/**/*.swift"]),
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":VitruvianCourierCore"],
)

# A render harness, not a test of how anything looks: it draws the views (message bubbles, the poll, the thread
# summary, the composer with its formatting bar, the pickers, the scheduled strip, Settings ▸ Messages), light and
# dark, to PNGs in the test's undeclared outputs (bazel-testlogs/.../VitruvianCourierViewTests/test.outputs), and asserts only
# that each drew at a sensible size. A person reads the PNGs before a view change ships: green tests have shipped a
# broken layout before. SwiftPM's VitruvianCourierViewTests is the same harness against the executable target.
# Large (900 s): on CI's hosted Macs the suite already took 254 s of medium's 300 on main, and each new snapshot
# pushes it closer; a timeout there fails the merge queue for no fault in the change (PR #4238).
swift_test(
    name = "VitruvianCourierViewTests",
    size = "large",
    srcs = glob(["Tests/VitruvianCourierViewTests/**/*.swift"]),
    # The made-up chats the test copy can open with: SeedScenarioSnapshotTests draws one (SeedScenario.swift).
    data = ["//apps/desktop/vitruvian-courier/seed:scenarios"],
    tags = [
        "exclusive",
        "manual",
    ],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":VitruvianCourierCore",
        ":VitruvianCourierViews",
    ],
)

# CFBundleShortVersionString and CFBundleVersion: the engine's go_binary stamps
# the same VITRUVIAN_COURIER_VERSION, so the two never differ.
apple_bundle_version(
    name = "version",
    build_version = VITRUVIAN_COURIER_VERSION,
    short_version_string = VITRUVIAN_COURIER_VERSION,
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
)

# The engine, built once for each CPU in --macos_cpus and joined with lipo. A
# plain build (one CPU) gives a one-architecture engine; the release builds
# with --macos_cpus=arm64,x86_64 (scripts/src/publish.rs), so the engine is
# universal like the app.
apple_universal_binary(
    name = "engine_universal",
    binary = "//apps/desktop/vitruvian-courier/engine/cmd/vitruvian-courier-engine",
    minimum_os_version = "14.0",
    platform_type = "macos",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
)

# The engine as the file the app bundles. macos_application's
# additional_contents keeps a file's path relative to its package, so this
# copy, `vitruvian-courier-engine` in this package, lands at
# Contents/Helpers/vitruvian-courier-engine. It is signed ad hoc here because the
# macOS linker signs only an arm64 binary: lipo's x86_64 half would be
# unsigned, and the app's signing refuses an unsigned helper. The install
# and the release sign it again with the Developer ID.
genrule(
    name = "engine_helper",
    srcs = [":engine_universal"],
    outs = ["vitruvian-courier-engine"],
    cmd = "cp $(location :engine_universal) $@ && chmod 755 $@ && /usr/bin/codesign --force --sign - --identifier com.vitruviansoftware.courier.engine $@",
    executable = True,
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
)

# bazel build --config=macos-app //apps/desktop/vitruvian-courier/app:VitruvianCourier
#
# The engine goes in Contents/Helpers, where the app looks for it
# (EngineLocation.swift).
#
# `manual`: macos_application transitions to a darwin platform, so
# target_compatible_with cannot keep it out of a Linux `//...`. AppIcon.icns is
# a loose resource (no asset catalog; see scripts/make-icon.swift). Ad-hoc
# signed.
macos_application(
    name = "VitruvianCourier",
    additional_contents = {
        ":engine_helper": "Helpers",
    },
    bundle_id = "com.vitruviansoftware.courier",
    bundle_name = "Vitruvian Courier",
    executable_name = "VitruvianCourier",
    infoplists = ["Resources/Info.plist"],
    minimum_os_version = "14.0",
    resources = ["Resources/AppIcon.icns"] + glob(["Resources/*.lproj/*.strings"]),
    tags = ["manual"],
    version = ":version",
    visibility = ["//apps/desktop/vitruvian-courier:__subpackages__"],
    deps = [":VitruvianCourierLib"],
)

# The test copy: the same app with its own bundle identifier (com.vitruviansoftware.courier.dev) and name, so a
# change can be tried in a real running Vitruvian Courier without touching the installed one. Its own identifier gives it its
# own settings, notification permission and Login Items entry, and makes it keep its data and Keychain items apart
# (VitruvianCourierCore's TestCopy). Never installed or released: :run_test_copy runs it. See README.md.
genrule(
    name = "test_copy_infoplist",
    srcs = ["Resources/Info.plist"],
    outs = ["TestCopy-Info.plist"],
    cmd = "sed -e 's|<string>com.vitruviansoftware.courier</string>|<string>com.vitruviansoftware.courier.dev</string>|' " +
          "-e 's|<string>Vitruvian Courier</string>|<string>Vitruvian Courier Test Copy</string>|' $< > $@",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
)

macos_application(
    name = "VitruvianCourierTestCopy",
    additional_contents = {
        "//apps/desktop/vitruvian-courier/app/seeded:engine_helper": "Helpers",
    },
    bundle_id = "com.vitruviansoftware.courier.dev",
    bundle_name = "Vitruvian Courier Test Copy",
    executable_name = "VitruvianCourier",
    infoplists = [":test_copy_infoplist"],
    minimum_os_version = "14.0",
    resources = ["Resources/AppIcon.icns"] + glob(["Resources/*.lproj/*.strings"]),
    tags = ["manual"],
    version = ":version",
    deps = [":VitruvianCourierLib"],
)

# bazel run --config=macos-app //apps/desktop/vitruvian-courier/app:run_test_copy [-- --data DIR] [-- --seed NAME]
#
# Unpacks :VitruvianCourierTestCopy into a temporary folder and opens it with VITRUVIAN_COURIER_DATA_DIR set to its own data folder
# (default: a folder under $TMPDIR). --seed NAME opens it full of the made-up chats of ../seed/scenarios/NAME.json,
# in a fresh $TMPDIR/vitruvian-courier-test-copy/seed-NAME (VITRUVIAN_COURIER_SEED). It refuses an app whose bundle identifier is not the test copy's, and a data
# folder that is the installed app's. It never touches /Applications/Vitruvian Courier.app.
rust_binary(
    name = "run_test_copy",
    srcs = ["scripts/src/bin/run_test_copy.rs"],
    args = [
        "$(rootpaths :VitruvianCourierTestCopy)",
        "--scenarios",
        "$(rootpaths //apps/desktop/vitruvian-courier/seed:scenarios)",
    ],
    data = [
        ":VitruvianCourierTestCopy",
        "//apps/desktop/vitruvian-courier/seed:scenarios",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":vitruvian_courier_scripts_lib"],
)

# The app Bazel built holds a working engine: Contents/Helpers/vitruvian-courier-engine
# runs on every CPU the app binary does and answers --help with its usage, and
# the bundle's version is VITRUVIAN_COURIER_VERSION. It reads the archive :VitruvianCourier already produced.
rust_test(
    name = "app_holds_engine_test",
    size = "small",
    srcs = ["scripts/src/bin/app_holds_engine.rs"],
    args = [
        VITRUVIAN_COURIER_VERSION,
        "$(rootpaths :VitruvianCourier)",
    ],
    crate_root = "scripts/src/bin/app_holds_engine.rs",
    data = [":VitruvianCourier"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    use_libtest_harness = False,
    deps = [":vitruvian_courier_scripts_lib"],
)

# Which engine each app bundles: :VitruvianCourier's must not hold the seed player (the made-up chats only the test copy may
# open with), and :VitruvianCourierTestCopy's must. It looks in each bundled engine for the seed package's Marker, read from
# its source. macOS-only and `manual`, like :app_holds_engine_test; the vitruvian-courier-app-macos unit below runs it.
rust_test(
    name = "release_engine_has_no_seed_test",
    size = "small",
    srcs = ["scripts/src/bin/release_engine_has_no_seed.rs"],
    args = [
        "$(rootpath //apps/desktop/vitruvian-courier/engine/internal/seed:seed.go)",
        "--release",
        "$(rootpaths :VitruvianCourier)",
        "--test-copy",
        "$(rootpaths :VitruvianCourierTestCopy)",
    ],
    crate_root = "scripts/src/bin/release_engine_has_no_seed.rs",
    data = [
        ":VitruvianCourier",
        ":VitruvianCourierTestCopy",
        "//apps/desktop/vitruvian-courier/engine/internal/seed:seed.go",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    use_libtest_harness = False,
    deps = [":vitruvian_courier_scripts_lib"],
)

# bazel run --config=macos-app //apps/desktop/vitruvian-courier/app:install [-- --dest DIR]
#
# Puts the app Bazel built into /Applications (or DIR) with Vitruvian Courier's own Telegram app ID added.
# It builds nothing but its data (VitruvianCourier.zip). The app ID never passes through a Bazel action,
# whose outputs can land in the remote cache: :inject-app-credentials adds it to the
# unpacked app afterwards, on this Mac, from the environment or the gitignored secret store
# (tools/sync-env-secrets), and signs the app again: the engine, then the app, with the Developer ID
# if one is installed (and the hardened runtime) and Resources/VitruvianCourier.entitlements. See README.md.
rust_binary(
    name = "install",
    srcs = ["scripts/src/bin/install.rs"],
    args = [
        "$(rootpath :inject-app-credentials)",
        "$(rootpaths :VitruvianCourier)",
    ],
    data = [
        "Resources/VitruvianCourier.entitlements",
        ":VitruvianCourier",
        ":inject-app-credentials",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    visibility = ["//apps/desktop/vitruvian-courier:__subpackages__"],
    deps = [":vitruvian_courier_scripts_lib"],
)

# The injector against a tiny stand-in app: it writes a valid TelegramApp.plist, signs the app so
# it passes codesign --verify, refuses bad values without printing them, and honours
# --allow-missing. A fake codesign proves how it signs (the engine before the app, the identifier,
# the hardened runtime and timestamp only with an identity, the entitlements). macOS-only (plutil, codesign) and `manual`: the vitruvian-courier-app-macos unit below
# runs it by label.
rust_test(
    name = "inject_app_credentials_test",
    size = "small",
    crate = ":vitruvian_courier_scripts_lib",
    # The same crate's tests as :vitruvian_courier_scripts_lib_test, so the same data:
    # publish's test reads version.bzl.
    data = [
        "Resources/VitruvianCourier.entitlements",
        "version.bzl",
    ],
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
        "$(rootpath //apps/desktop/vitruvian-courier/engine/cmd/vitruvian-courier-engine)",
        "$(rootpath Sources/VitruvianCourierCore/EngineSupervisor.swift)",
        "$(rootpath Sources/VitruvianCourierCore/Protocol.swift)",
        "$(rootpaths //apps/desktop/vitruvian-courier/protocol)",
    ],
    crate_root = "scripts/src/bin/engine_contract.rs",
    data = [
        "Sources/VitruvianCourierCore/EngineSupervisor.swift",
        "Sources/VitruvianCourierCore/Protocol.swift",
        "//apps/desktop/vitruvian-courier/engine/cmd/vitruvian-courier-engine",
        "//apps/desktop/vitruvian-courier/protocol",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    use_libtest_harness = False,
    deps = [":vitruvian_courier_scripts_lib"],
)

pipeline_unit(
    name = "vitruvian-courier-app-macos",
    persona = "frontend",
    runner = "xcode-27",
    test_targets = [
        ":VitruvianCourierCoreTests",
        ":VitruvianCourierViewTests",
        ":app_holds_engine_test",
        ":engine_contract_test",
        ":inject_app_credentials_test",
        ":release_engine_has_no_seed_test",
    ],
    tier = "L1",
    # A cold build of the engine it bundles is libsignal's 2,000+ actions
    # (../engine/BUILD); the remote cache makes later runs much shorter.
    timeout_minutes = 60,
)

# bazel run //apps/desktop/vitruvian-courier/app:publish [-- --dry-run]
#
# The release: builds Vitruvian Courier.app for arm64 and x86_64 (it runs `bazel build`
# itself, with --config=macos-app --macos_cpus=arm64,x86_64), checks the app
# and its engine run on both, adds Vitruvian Courier's Telegram app ID, and hands the app
# to //tools/desktop-package to sign (engine, then app, hardened runtime,
# Resources/VitruvianCourier.entitlements), notarise, make the DMGs, ZIP, checksums and
# Homebrew cask, and on a real release upload them. --dry-run uploads and
# pushes nothing. .github/workflows/vitruvian-courier-release.yaml runs it when a
# release-please release is cut; scripts/src/publish.rs says what it reads.
rust_binary(
    name = "publish",
    srcs = ["scripts/src/bin/publish.rs"],
    args = [
        "$(rootpath :inject-app-credentials)",
        "$(rootpath Resources/VitruvianCourier.entitlements)",
        "$(rootpath //tools/desktop-package:package-desktop)",
        "$(rootpath //tools/sync-downloads:sync_downloads)",
    ],
    data = [
        "Resources/VitruvianCourier.entitlements",
        ":inject-app-credentials",
        "//tools/desktop-package:package-desktop",
        "//tools/sync-downloads:sync_downloads",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":vitruvian_courier_scripts_lib"],
)

# --- Rust ports of vitruvian-courier app scripts ------------------------------

rust_library(
    name = "vitruvian_courier_scripts_lib",
    srcs = glob(
        ["scripts/src/**/*.rs"],
        exclude = ["scripts/src/bin/*.rs"],
    ),
    crate_name = "vitruvian_courier_scripts_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_test(
    name = "vitruvian_courier_scripts_lib_test",
    size = "small",
    crate = ":vitruvian_courier_scripts_lib",
    # publish's test reads the real version.bzl, as release-please rewrites it.
    data = ["version.bzl"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "inject-app-credentials",
    srcs = ["scripts/src/bin/inject_app_credentials.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/desktop/vitruvian-courier:__subpackages__"],
    deps = [":vitruvian_courier_scripts_lib"],
)

alias(
    name = "inject_app_credentials",
    actual = ":inject-app-credentials",
    visibility = ["//apps/desktop/vitruvian-courier:__subpackages__"],
)

rust_binary(
    name = "engine-contract",
    srcs = ["scripts/src/bin/engine_contract.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/desktop/vitruvian-courier:__subpackages__"],
    deps = [":vitruvian_courier_scripts_lib"],
)

alias(
    name = "engine_contract",
    actual = ":engine-contract",
    visibility = ["//apps/desktop/vitruvian-courier:__subpackages__"],
)

rust_binary(
    name = "app-holds-engine",
    srcs = ["scripts/src/bin/app_holds_engine.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/desktop/vitruvian-courier:__subpackages__"],
    deps = [":vitruvian_courier_scripts_lib"],
)

alias(
    name = "app_holds_engine",
    actual = ":app-holds-engine",
    visibility = ["//apps/desktop/vitruvian-courier:__subpackages__"],
)
