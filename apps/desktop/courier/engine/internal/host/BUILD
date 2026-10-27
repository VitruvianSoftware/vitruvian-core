load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "host",
    srcs = ["host.go"],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/host",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
    deps = [
        "//apps/desktop/courier/engine/internal/ids",
        "//apps/desktop/courier/engine/internal/localmatrix",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/sqlite",
        "//apps/desktop/courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
        "@fi_mau_go_util//dbutil",
        "@in_gopkg_yaml_v3//:yaml_v3",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//bridgev2/bridgeconfig",
        "@net_maunium_go_mautrix//bridgev2/commands",
        "@net_maunium_go_mautrix//bridgev2/networkid",
        "@net_maunium_go_mautrix//event",
    ],
)

go_test(
    name = "host_test",
    srcs = ["host_test.go"],
    embed = [":host"],
    deps = [
        "//apps/desktop/courier/engine/internal/fakenet",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/sqlite",
        "//apps/desktop/courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
        "@fi_mau_go_util//configupgrade",
        "@net_maunium_go_mautrix//:mautrix",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//event",
        "@net_maunium_go_mautrix//id",
    ],
)
