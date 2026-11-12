load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "trafficproxy",
    srcs = ["proxy.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/trafficproxy",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
)

go_test(
    name = "trafficproxy_test",
    srcs = ["proxy_test.go"],
    embed = [":trafficproxy"],
)
