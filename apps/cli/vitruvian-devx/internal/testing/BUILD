load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "testing",
    srcs = ["ephemeral.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/testing",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
    deps = ["//apps/cli/vitruvian-devx/internal/database"],
)
