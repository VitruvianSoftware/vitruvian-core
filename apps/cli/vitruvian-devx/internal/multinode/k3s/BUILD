load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "k3s",
    srcs = [
        "advanced.go",
        "cilium.go",
        "k3s.go",
        "recipe.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/k3s",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
    deps = ["//apps/cli/vitruvian-devx/internal/multinode/remote"],
)

go_test(
    name = "k3s_test",
    srcs = [
        "advanced_test.go",
        "cilium_test.go",
        "k3s_defaults_test.go",
        "k3s_exec_test.go",
        "recipe_test.go",
    ],
    embed = [":k3s"],
    deps = ["//apps/cli/vitruvian-devx/internal/multinode/remote"],
)
