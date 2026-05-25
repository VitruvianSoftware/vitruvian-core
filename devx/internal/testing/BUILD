load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "testing",
    srcs = ["ephemeral.go"],
    importpath = "github.com/VitruvianSoftware/devx/internal/testing",
    visibility = ["//devx:__subpackages__"],
    deps = ["//devx/internal/database"],
)
