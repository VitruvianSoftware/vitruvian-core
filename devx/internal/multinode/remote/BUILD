load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "remote",
    srcs = ["remote.go"],
    importpath = "github.com/VitruvianSoftware/devx/internal/multinode/remote",
    visibility = ["//devx:__subpackages__"],
)

go_test(
    name = "remote_test",
    srcs = ["remote_test.go"],
    embed = [":remote"],
)
