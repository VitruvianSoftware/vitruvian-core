load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")

go_library(
    name = "courier-engine-cli_lib",
    srcs = [
        "lock.go",
        "main.go",
    ],
    importpath = "github.com/VitruvianSoftware/courier/engine/cmd/courier-engine-cli",
    visibility = ["//visibility:private"],
    deps = [
        "//apps/desktop/courier/engine/internal/host",
        "//apps/desktop/courier/engine/internal/ids",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/store",
        "@com_github_mdp_qrterminal_v3//:qrterminal",
        "@com_github_rs_zerolog//:zerolog",
        "@fi_mau_go_mautrix_whatsapp//pkg/connector",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//event",
        "@net_maunium_go_mautrix//id",
    ],
)

go_binary(
    name = "courier-engine-cli",
    embed = [":courier-engine-cli_lib"],
    visibility = ["//visibility:public"],
)

go_test(
    name = "courier-engine-cli_test",
    srcs = [
        "lock_test.go",
        "main_test.go",
    ],
    embed = [":courier-engine-cli_lib"],
    deps = [
        "//apps/desktop/courier/engine/internal/fakenet",
        "//apps/desktop/courier/engine/internal/host",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
        "@net_maunium_go_mautrix//bridgev2",
    ],
)
