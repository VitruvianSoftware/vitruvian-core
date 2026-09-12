load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "updater",
    srcs = [
        "updater.go",
        "upgrade.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/updater",
    visibility = ["//apps/cli/devx:__subpackages__"],
)
