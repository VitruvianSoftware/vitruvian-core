load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "util",
    srcs = ["util.go"],
    importpath = "github.com/VitruvianSoftware/devx/internal/multinode/util",
    visibility = ["//apps/cli/devx:__subpackages__"],
    deps = [
        "//apps/cli/devx/internal/multinode/config",
        "//apps/cli/devx/internal/multinode/remote",
    ],
)
