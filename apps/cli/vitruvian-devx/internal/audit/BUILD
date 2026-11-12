load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "audit",
    srcs = ["audit.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/audit",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
    deps = ["//apps/cli/vitruvian-devx/internal/provider"],
)
