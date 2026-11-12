load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "projectcfg",
    srcs = ["projectcfg.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/projectcfg",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
    deps = [
        "//apps/cli/vitruvian-devx/internal/config",
        "@in_gopkg_yaml_v3//:yaml_v3",
    ],
)

go_test(
    name = "projectcfg_test",
    srcs = ["projectcfg_test.go"],
    embed = [":projectcfg"],
)
