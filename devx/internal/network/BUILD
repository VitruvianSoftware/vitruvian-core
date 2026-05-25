load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "network",
    srcs = ["ports.go"],
    importpath = "github.com/VitruvianSoftware/devx/internal/network",
    visibility = ["//devx:__subpackages__"],
)

go_test(
    name = "network_test",
    srcs = ["ports_test.go"],
    embed = [":network"],
)
