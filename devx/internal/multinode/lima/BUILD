load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "lima",
    srcs = [
        "lima.go",
        "mounts.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/multinode/lima",
    visibility = ["//devx:__subpackages__"],
    deps = [
        "//devx/internal/multinode/config",
        "//devx/internal/multinode/remote",
        "//devx/internal/multinode/util",
        "@in_gopkg_yaml_v3//:yaml_v3",
    ],
)

go_test(
    name = "lima_test",
    srcs = ["mounts_test.go"],
    embed = [":lima"],
    deps = ["//devx/internal/multinode/config"],
)
