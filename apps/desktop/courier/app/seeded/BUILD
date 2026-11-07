# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-or-later

# The test copy's engine: courier-engine-seeded, the same program built with the courierseed tag, so the test copy
# can open full of made-up chats (COURIER_SEED, ../../seed/README.md). Joined and signed exactly as the released
# engine in ../BUILD, under the same identifier. Only :CourierTestCopy bundles it; ../BUILD's
# release_engine_has_no_seed_test checks that :Courier never does.
#
# Its own package because the file must be named courier-engine, as the app looks for it, and macos_application's
# additional_contents keeps a file's path relative to its package: this package's courier-engine lands at
# Contents/Helpers/courier-engine, where ../BUILD's own courier-engine already is the released engine.

load("@build_bazel_rules_apple//apple:apple.bzl", "apple_universal_binary")

apple_universal_binary(
    name = "engine_universal",
    binary = "//apps/desktop/courier/engine/cmd/courier-engine:courier-engine-seeded",
    minimum_os_version = "14.0",
    platform_type = "macos",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
)

genrule(
    name = "engine_helper",
    srcs = [":engine_universal"],
    outs = ["courier-engine"],
    cmd = "cp $(location :engine_universal) $@ && chmod 755 $@ && /usr/bin/codesign --force --sign - --identifier com.vitruviansoftware.courier.engine $@",
    executable = True,
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    visibility = ["//apps/desktop/courier/app:__pkg__"],
)
