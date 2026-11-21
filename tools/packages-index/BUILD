load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")

go_library(
    name = "packages-index_lib",
    srcs = [
        "index.go",
        "main.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/packages-index",
    visibility = ["//visibility:private"],
    deps = ["@in_gopkg_yaml_v3//:yaml_v3"],
)

go_binary(
    name = "packages-index",
    embed = [":packages-index_lib"],
    visibility = ["//visibility:public"],
)

go_test(
    name = "packages-index_test",
    srcs = ["index_test.go"],
    embed = [":packages-index_lib"],
)
