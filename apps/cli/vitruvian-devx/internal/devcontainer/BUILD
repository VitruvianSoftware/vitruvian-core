load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "devcontainer",
    srcs = ["config.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/devcontainer",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
)

go_test(
    name = "devcontainer_test",
    srcs = ["config_test.go"],
    embed = [":devcontainer"],
)
