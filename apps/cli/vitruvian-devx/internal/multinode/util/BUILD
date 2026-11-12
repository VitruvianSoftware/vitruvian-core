load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "util",
    srcs = ["util.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/util",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
    deps = [
        "//apps/cli/vitruvian-devx/internal/multinode/config",
        "//apps/cli/vitruvian-devx/internal/multinode/remote",
    ],
)
