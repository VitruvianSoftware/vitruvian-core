load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "cloud",
    srcs = ["emulator.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/cloud",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
)

go_test(
    name = "cloud_test",
    srcs = ["emulator_test.go"],
    embed = [":cloud"],
)
