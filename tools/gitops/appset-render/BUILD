load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")

go_library(
    name = "appset_render_lib",
    srcs = ["main.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/gitops/appset-render",
    visibility = ["//visibility:private"],
)

go_binary(
    name = "appset-render",
    embed = [":appset_render_lib"],
    visibility = ["//visibility:public"],
)

alias(
    name = "appset_render",
    actual = ":appset-render",
    visibility = ["//visibility:public"],
)

go_test(
    name = "appset_render_test",
    size = "small",
    srcs = ["main_test.go"],
    embed = [":appset_render_lib"],
)

alias(
    name = "appset-render_test",
    actual = ":appset_render_test",
)
