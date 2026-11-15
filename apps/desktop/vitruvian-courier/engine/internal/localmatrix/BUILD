load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "localmatrix",
    srcs = [
        "arrived.go",
        "connector.go",
        "intent.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-courier/engine/internal/localmatrix",
    visibility = ["//apps/desktop/vitruvian-courier/engine:__subpackages__"],
    deps = [
        "//apps/desktop/vitruvian-courier/engine/internal/ids",
        "//apps/desktop/vitruvian-courier/engine/internal/media",
        "//apps/desktop/vitruvian-courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
        "@net_maunium_go_mautrix//:mautrix",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//bridgev2/database",
        "@net_maunium_go_mautrix//bridgev2/networkid",
        "@net_maunium_go_mautrix//bridgev2/status",
        "@net_maunium_go_mautrix//event",
        "@net_maunium_go_mautrix//id",
    ],
)

go_test(
    name = "localmatrix_test",
    srcs = [
        "arrived_test.go",
        "connector_test.go",
        "intent_test.go",
    ],
    embed = [":localmatrix"],
    deps = [
        "//apps/desktop/vitruvian-courier/engine/internal/fakenet",
        "//apps/desktop/vitruvian-courier/engine/internal/ids",
        "//apps/desktop/vitruvian-courier/engine/internal/media",
        "//apps/desktop/vitruvian-courier/engine/internal/sqlite",
        "//apps/desktop/vitruvian-courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
        "@net_maunium_go_mautrix//:mautrix",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//bridgev2/bridgeconfig",
        "@net_maunium_go_mautrix//bridgev2/commands",
        "@net_maunium_go_mautrix//bridgev2/database",
        "@net_maunium_go_mautrix//bridgev2/networkid",
        "@net_maunium_go_mautrix//bridgev2/status",
        "@net_maunium_go_mautrix//event",
        "@net_maunium_go_mautrix//id",
    ],
)
