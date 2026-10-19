load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")

go_library(
    name = "github-relay_lib",
    srcs = [
        "clock.go",
        "config.go",
        "github.go",
        "hub.go",
        "main.go",
        "metrics.go",
        "normalize.go",
        "server.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/apps/services/github-relay",
    visibility = ["//visibility:private"],
)

go_binary(
    name = "github-relay",
    embed = [":github-relay_lib"],
    visibility = ["//visibility:public"],
)

go_test(
    name = "github-relay_test",
    size = "small",
    srcs = [
        "config_test.go",
        "events_test.go",
        "helpers_test.go",
        "webhook_test.go",
    ],
    embed = [":github-relay_lib"],
)
