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
        "rooms.go",
        "send.go",
        "sync.go",
    ],
    cdeps = ["//apps/desktop/vitruvian-courier/gchat:gchat_ffi"],
    cgo = True,
    importpath = "github.com/VitruvianSoftware/vitruvian-courier/engine/internal/gchat",
    visibility = ["//apps/desktop/vitruvian-courier/engine:__subpackages__"],
    deps = [
        "//apps/desktop/vitruvian-courier/engine/internal/gchat/pb",
        "@com_github_rs_zerolog//:zerolog",
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
        "rooms.go",
        "send.go",
        "sync.go",
        "thread_backfill_test.go",
        "threads_test.go",
    ],
    cdeps = ["//apps/desktop/vitruvian-courier/gchat:gchat_ffi_test_loopback"],
    cgo = True,
    importpath = "github.com/VitruvianSoftware/vitruvian-courier/engine/internal/gchat",
    visibility = ["//apps/desktop/vitruvian-courier:__subpackages__"],
    deps = [
        "//apps/desktop/vitruvian-courier/engine/internal/actions",
        "//apps/desktop/vitruvian-courier/engine/internal/engine",
        "//apps/desktop/vitruvian-courier/engine/internal/gchat/pb",
        "//apps/desktop/vitruvian-courier/engine/internal/host",
        "//apps/desktop/vitruvian-courier/engine/internal/media",
        "//apps/desktop/vitruvian-courier/engine/internal/rpc",
        "//apps/desktop/vitruvian-courier/engine/internal/store",
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
