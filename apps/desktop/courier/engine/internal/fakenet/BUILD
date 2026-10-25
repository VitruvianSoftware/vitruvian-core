load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "fakenet",
    srcs = [
        "fakenet.go",
        "script.go",
        "wait.go",
    ],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/fakenet",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
    deps = [
        "//apps/desktop/courier/engine/internal/ids",
        "//apps/desktop/courier/engine/internal/store",
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
    name = "fakenet_test",
    srcs = ["glue_test.go"],
    embed = [":fakenet"],
    deps = [
        "//apps/desktop/courier/engine/internal/ids",
        "//apps/desktop/courier/engine/internal/localmatrix",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/sqlite",
        "//apps/desktop/courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
        "@fi_mau_go_util//jsontime",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//bridgev2/bridgeconfig",
        "@net_maunium_go_mautrix//bridgev2/commands",
        "@net_maunium_go_mautrix//event",
        "@net_maunium_go_mautrix//id",
    ],
)
