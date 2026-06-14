load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")

go_library(
    name = "conflict_precheck_lib",
    srcs = ["main.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/copybara/conflict_precheck",
    visibility = ["//visibility:private"],
)

go_binary(
    name = "conflict_precheck",
    embed = [":conflict_precheck_lib"],
    visibility = ["//visibility:public"],
)

go_test(
    name = "conflict_precheck_test",
    srcs = ["main_test.go"],
    embed = [":conflict_precheck_lib"],
)
