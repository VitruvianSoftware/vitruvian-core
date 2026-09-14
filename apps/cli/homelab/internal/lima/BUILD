load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "lima",
    srcs = ["lima.go"],
    importpath = "github.com/VitruvianSoftware/homelab/internal/lima",
    visibility = ["//apps/cli/homelab:__subpackages__"],
    deps = [
        "//apps/cli/homelab/internal/config",
        "//apps/cli/homelab/internal/remote",
    ],
)
