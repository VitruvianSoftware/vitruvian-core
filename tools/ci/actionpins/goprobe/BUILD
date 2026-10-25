load("@rules_go//go:def.bzl", "go_binary", "go_library")

go_library(
    name = "goprobe_lib",
    srcs = ["main.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/ci/actionpins/goprobe",
    visibility = ["//visibility:private"],
    deps = ["//tools/ci/actionpins"],
)

go_binary(
    name = "goprobe",
    embed = [":goprobe_lib"],
    visibility = ["//visibility:public"],
)
