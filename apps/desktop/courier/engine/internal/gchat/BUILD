# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-only

load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "gchat",
    srcs = [
        "client.go",
        "connector.go",
        "ffi.go",
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
        "@net_maunium_go_mautrix//bridgev2/status",
        "@net_maunium_go_mautrix//event",
    ],
)

go_test(
    name = "gchat_test",
    srcs = ["gchat_test.go"],
    embed = [":gchat"],
    deps = [
        "//apps/desktop/courier/engine/internal/host",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//bridgev2/networkid",
    ],
)
