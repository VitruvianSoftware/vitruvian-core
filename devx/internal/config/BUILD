load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "config",
    srcs = [
        "config.go",
        "findconfig.go",
        "local.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/config",
    visibility = ["//devx:__subpackages__"],
    deps = ["@in_gopkg_yaml_v3//:yaml_v3"],
)

go_test(
    name = "config_test",
    srcs = [
        "config_test.go",
        "findconfig_test.go",
        "local_test.go",
    ],
    embed = [":config"],
)
