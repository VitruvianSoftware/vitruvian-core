load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "lima",
    srcs = ["lima.go"],
    importpath = "github.com/VitruvianSoftware/devx/internal/multinode/lima",
    visibility = ["//devx:__subpackages__"],
    deps = [
        "//devx/internal/multinode/config",
        "//devx/internal/multinode/remote",
        "//devx/internal/multinode/util",
    ],
)
