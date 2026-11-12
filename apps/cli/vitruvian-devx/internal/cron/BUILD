load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "cron",
    srcs = ["cron.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/cron",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
)

go_test(
    name = "cron_test",
    srcs = ["cron_test.go"],
    embed = [":cron"],
)
