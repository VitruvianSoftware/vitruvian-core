load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "engine",
    srcs = ["engine.go"],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/engine",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
    deps = [
        "//apps/desktop/courier/engine/internal/host",
        "//apps/desktop/courier/engine/internal/ids",
        "//apps/desktop/courier/engine/internal/localmatrix",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
        "@net_maunium_go_mautrix//bridgev2",
    ],
)

go_test(
    name = "engine_test",
    srcs = ["engine_test.go"],
    embed = [":engine"],
    deps = [
        "//apps/desktop/courier/engine/internal/fakenet",
        "//apps/desktop/courier/engine/internal/ids",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//assert",
        "@com_github_stretchr_testify//require",
        "@fi_mau_go_util//configupgrade",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//bridgev2/database",
        "@net_maunium_go_mautrix//bridgev2/networkid",
        "@net_maunium_go_mautrix//event",
        "@net_maunium_go_mautrix//id",
    ],
)
