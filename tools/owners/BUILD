load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")

go_library(
    name = "owners_lib",
    srcs = [
        "coverage.go",
        "engine.go",
        "main.go",
        "schema.go",
        "validate.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/owners",
    visibility = ["//visibility:private"],
    deps = [
        "@in_gopkg_yaml_v3//:yaml_v3",
    ],
)

go_binary(
    name = "owners",
    embed = [":owners_lib"],
    visibility = ["//visibility:public"],
)

go_test(
    name = "owners_test",
    size = "small",
    srcs = ["main_test.go"],
    embed = [":owners_lib"],
)
