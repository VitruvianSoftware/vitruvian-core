load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "lima",
    srcs = [
        "keeper.go",
        "lima.go",
        "mounts.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/lima",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
    deps = [
        "//apps/cli/vitruvian-devx/internal/multinode/config",
        "//apps/cli/vitruvian-devx/internal/multinode/remote",
        "//apps/cli/vitruvian-devx/internal/multinode/util",
        "@in_gopkg_yaml_v3//:yaml_v3",
    ],
)

go_test(
    name = "lima_test",
    srcs = [
        "keeper_test.go",
        "mounts_test.go",
    ],
    embed = [":lima"],
    deps = ["//apps/cli/vitruvian-devx/internal/multinode/config"],
)
