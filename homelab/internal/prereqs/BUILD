load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "prereqs",
    srcs = ["prereqs.go"],
    importpath = "github.com/VitruvianSoftware/homelab/internal/prereqs",
    visibility = ["//homelab:__subpackages__"],
    deps = [
        "//homelab/internal/config",
        "//homelab/internal/remote",
    ],
)
