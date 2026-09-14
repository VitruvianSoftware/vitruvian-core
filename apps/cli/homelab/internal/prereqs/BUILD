load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "prereqs",
    srcs = ["prereqs.go"],
    importpath = "github.com/VitruvianSoftware/homelab/internal/prereqs",
    visibility = ["//apps/cli/homelab:__subpackages__"],
    deps = [
        "//apps/cli/homelab/internal/config",
        "//apps/cli/homelab/internal/remote",
    ],
)
