load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "imessage",
    srcs = [
        "chatdb.go",
        "connector.go",
        "send.go",
    ],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/imessage",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
    deps = [
        "@fi_mau_go_util//configupgrade",
        "@fi_mau_go_util//dbutil/litestream",
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
    name = "imessage_test",
    srcs = ["imessage_test.go"],
    embed = [":imessage"],
    deps = [
        "//apps/desktop/courier/engine/internal/host",
        "//apps/desktop/courier/engine/internal/ids",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//event",
        "@net_maunium_go_mautrix//id",
    ],
)
