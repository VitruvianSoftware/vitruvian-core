load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "cloud",
    srcs = ["emulator.go"],
    importpath = "github.com/VitruvianSoftware/devx/internal/cloud",
    visibility = ["//devx:__subpackages__"],
)

go_test(
    name = "cloud_test",
    srcs = ["emulator_test.go"],
    embed = [":cloud"],
)
