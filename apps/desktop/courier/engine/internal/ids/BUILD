load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "ids",
    srcs = ["ids.go"],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/ids",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
    deps = [
        "@net_maunium_go_mautrix//bridgev2/networkid",
        "@net_maunium_go_mautrix//id",
    ],
)

go_test(
    name = "ids_test",
    srcs = ["ids_test.go"],
    embed = [":ids"],
    deps = [
        "@com_github_stretchr_testify//require",
        "@net_maunium_go_mautrix//bridgev2/networkid",
        "@net_maunium_go_mautrix//id",
    ],
)
