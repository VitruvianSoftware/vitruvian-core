load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "util",
    srcs = ["util.go"],
    importpath = "github.com/VitruvianSoftware/devx/internal/multinode/util",
    visibility = ["//devx:__subpackages__"],
    deps = [
        "//devx/internal/multinode/config",
        "//devx/internal/multinode/remote",
    ],
)
