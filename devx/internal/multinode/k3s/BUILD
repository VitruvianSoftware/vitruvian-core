load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "k3s",
    srcs = [
        "advanced.go",
        "k3s.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/multinode/k3s",
    visibility = ["//devx:__subpackages__"],
    deps = ["//devx/internal/multinode/remote"],
)
