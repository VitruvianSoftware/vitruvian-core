load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "ship",
    srcs = [
        "hook.go",
        "ship.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/ship",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
    deps = ["//apps/cli/vitruvian-devx/internal/telemetry"],
)

go_test(
    name = "ship_test",
    srcs = [
        "gitpush_test.go",
        "ship_test.go",
    ],
    embed = [":ship"],
)
