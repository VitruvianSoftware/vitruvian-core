load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "prereqs",
    srcs = ["check.go"],
    importpath = "github.com/VitruvianSoftware/devx/internal/prereqs",
    visibility = ["//devx:__subpackages__"],
)

go_test(
    name = "prereqs_test",
    srcs = ["check_test.go"],
    deps = [":prereqs"],
)
