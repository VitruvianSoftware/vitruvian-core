load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "nuke",
    srcs = ["nuke.go"],
    importpath = "github.com/VitruvianSoftware/devx/internal/nuke",
    visibility = ["//apps/cli/devx:__subpackages__"],
    deps = ["//apps/cli/devx/internal/provider"],
)
