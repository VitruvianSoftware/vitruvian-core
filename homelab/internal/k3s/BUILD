load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "k3s",
    srcs = [
        "advanced.go",
        "k3s.go",
    ],
    importpath = "github.com/VitruvianSoftware/homelab/internal/k3s",
    visibility = ["//homelab:__subpackages__"],
    deps = ["//homelab/internal/remote"],
)
