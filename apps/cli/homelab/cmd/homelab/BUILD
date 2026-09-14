load("@rules_go//go:def.bzl", "go_binary", "go_library")

go_library(
    name = "homelab_lib",
    srcs = ["main.go"],
    importpath = "github.com/VitruvianSoftware/homelab/cmd/homelab",
    visibility = ["//visibility:private"],
    deps = ["//apps/cli/homelab/internal/cmd"],
)

go_binary(
    name = "homelab",
    embed = [":homelab_lib"],
    visibility = ["//apps/cli/homelab:__subpackages__"],
)
