load("@rules_go//go:def.bzl", "go_library", "go_test")

go_test(
    name = "timers_test",
    srcs = ["timers_test.go"],
    embed = [":timers"],
    deps = [
        "//apps/desktop/courier/engine/internal/entitlement",
        "//apps/desktop/courier/engine/internal/ids",
        "//apps/desktop/courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
    ],
)

go_library(
    name = "timers",
    srcs = ["timers.go"],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/timers",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
    deps = [
        "//apps/desktop/courier/engine/internal/entitlement",
        "//apps/desktop/courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
    ],
)
