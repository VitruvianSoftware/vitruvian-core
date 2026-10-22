load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "actions",
    srcs = [
        "actions.go",
        "chatstate.go",
        "features.go",
    ],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/actions",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
    deps = [
        "//apps/desktop/courier/engine/internal/engine",
        "//apps/desktop/courier/engine/internal/host",
        "//apps/desktop/courier/engine/internal/ids",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/richtext",
        "//apps/desktop/courier/engine/internal/store",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//event",
        "@net_maunium_go_mautrix//id",
    ],
)

go_test(
    name = "actions_test",
    srcs = [
        "actions_test.go",
        "chatstate_test.go",
        "features_test.go",
    ],
    embed = [":actions"],
    deps = [
        "//apps/desktop/courier/engine/internal/engine",
        "//apps/desktop/courier/engine/internal/fakenet",
        "//apps/desktop/courier/engine/internal/ids",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/richtext",
        "//apps/desktop/courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
        "@fi_mau_go_util//jsontime",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//event",
        "@net_maunium_go_mautrix//id",
    ],
)
