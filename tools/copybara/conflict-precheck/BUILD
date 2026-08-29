load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")

go_library(
    name = "conflict_precheck_lib",
    srcs = ["main.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/copybara/conflict-precheck",
    visibility = ["//visibility:private"],
)

go_binary(
    name = "conflict-precheck",
    embed = [":conflict_precheck_lib"],
    visibility = ["//visibility:public"],
)

alias(
    name = "conflict_precheck",
    actual = ":conflict-precheck",
    visibility = ["//visibility:public"],
)

go_test(
    name = "conflict_precheck_test",
    srcs = ["main_test.go"],
    embed = [":conflict_precheck_lib"],
)

alias(
    name = "conflict-precheck_test",
    actual = ":conflict_precheck_test",
)
