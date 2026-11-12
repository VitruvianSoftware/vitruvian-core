load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "config",
    srcs = [
        "config.go",
        "validate.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/config",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
    deps = [
        "//apps/cli/vitruvian-devx/internal/config",
        "@in_gopkg_yaml_v3//:yaml_v3",
    ],
)

go_test(
    name = "config_test",
    srcs = [
        "config_test.go",
        "kind_test.go",
        "mounts_test.go",
        "validate_test.go",
    ],
    embed = [":config"],
    deps = ["@in_gopkg_yaml_v3//:yaml_v3"],
)
