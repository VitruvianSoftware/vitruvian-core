load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "config",
    srcs = [
        "config.go",
        "validate.go",
    ],
    importpath = "github.com/VitruvianSoftware/homelab/internal/config",
    visibility = ["//homelab:__subpackages__"],
    deps = ["@in_gopkg_yaml_v3//:yaml_v3"],
)

go_test(
    name = "config_test",
    srcs = [
        "config_test.go",
        "validate_test.go",
    ],
    embed = [":config"],
)
