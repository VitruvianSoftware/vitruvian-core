# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-only
#
# gazelle:ignore

load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "gchat",
    srcs = [
        "client.go",
        "connector.go",
        "ffi.go",
        "media.go",
        "send.go",
        "sync.go",
    ],
    cdeps = ["//apps/desktop/courier/gchat:gchat_ffi"],
    cgo = True,
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/gchat",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
    deps = [
        "@fi_mau_go_util//configupgrade",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//bridgev2/database",
        "@net_maunium_go_mautrix//bridgev2/networkid",
        "@net_maunium_go_mautrix//bridgev2/simplevent",
        "@net_maunium_go_mautrix//bridgev2/status",
        "@net_maunium_go_mautrix//event",
        "@net_maunium_go_mautrix//id",
    ],
)

go_test(
    name = "gchat_test",
    srcs = [
        "client.go",
        "connector.go",
        "ffi.go",
        "gchat_test.go",
        "loopback_test.go",
        "media.go",
        "send.go",
        "sync.go",
    ],
    cdeps = ["//apps/desktop/courier/gchat:gchat_ffi_test_loopback"],
    cgo = True,
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/gchat",
    deps = [
        "//apps/desktop/courier/engine/internal/host",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
        "@fi_mau_go_util//configupgrade",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//bridgev2/database",
        "@net_maunium_go_mautrix//bridgev2/networkid",
        "@net_maunium_go_mautrix//bridgev2/simplevent",
        "@net_maunium_go_mautrix//bridgev2/status",
        "@net_maunium_go_mautrix//event",
        "@net_maunium_go_mautrix//id",
    ],
)
