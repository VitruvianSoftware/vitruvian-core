load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "audit",
    srcs = ["audit.go"],
    importpath = "github.com/VitruvianSoftware/devx/internal/audit",
    visibility = ["//apps/cli/devx:__subpackages__"],
    deps = ["//apps/cli/devx/internal/provider"],
)
