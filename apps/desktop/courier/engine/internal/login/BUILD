load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "login",
    srcs = [
        "cookies.go",
        "fields.go",
        "login.go",
        "steps.go",
    ],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/login",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
    deps = [
        "//apps/desktop/courier/engine/internal/engine",
        "//apps/desktop/courier/engine/internal/store",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//bridgev2/status",
    ],
)

go_test(
    name = "login_test",
    srcs = ["login_test.go"],
    embed = [":login"],
    deps = [
        "//apps/desktop/courier/engine/internal/engine",
        "//apps/desktop/courier/engine/internal/fakenet",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//bridgev2/database",
        "@net_maunium_go_mautrix//bridgev2/networkid",
    ],
)
