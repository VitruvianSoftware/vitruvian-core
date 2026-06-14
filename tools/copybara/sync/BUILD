load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")

go_library(
    name = "sync_lib",
    srcs = ["main.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/copybara/sync",
    visibility = ["//visibility:private"],
)

go_binary(
    name = "sync",
    embed = [":sync_lib"],
    visibility = ["//visibility:public"],
)

go_test(
    name = "sync_test",
    srcs = ["main_test.go"],
    embed = [":sync_lib"],
)
