load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "ship",
    srcs = [
        "hook.go",
        "ship.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/ship",
    visibility = ["//devx:__subpackages__"],
    deps = ["//devx/internal/telemetry"],
)

go_test(
    name = "ship_test",
    srcs = ["ship_test.go"],
    embed = [":ship"],
)
