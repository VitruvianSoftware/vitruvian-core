load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "prereqs",
    srcs = ["prereqs.go"],
    importpath = "github.com/VitruvianSoftware/devx/internal/multinode/prereqs",
    visibility = ["//devx:__subpackages__"],
    deps = [
        "//devx/internal/multinode/config",
        "//devx/internal/multinode/remote",
        "//devx/internal/multinode/util",
    ],
)
