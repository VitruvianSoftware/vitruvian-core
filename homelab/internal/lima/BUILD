load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "lima",
    srcs = ["lima.go"],
    importpath = "github.com/VitruvianSoftware/homelab/internal/lima",
    visibility = ["//homelab:__subpackages__"],
    deps = [
        "//homelab/internal/config",
        "//homelab/internal/remote",
    ],
)
