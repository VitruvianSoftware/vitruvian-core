load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "trafficproxy",
    srcs = ["proxy.go"],
    importpath = "github.com/VitruvianSoftware/devx/internal/trafficproxy",
    visibility = ["//devx:__subpackages__"],
)

go_test(
    name = "trafficproxy_test",
    srcs = ["proxy_test.go"],
    embed = [":trafficproxy"],
)
