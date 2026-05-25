load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "telemetry",
    srcs = [
        "dashboard.go",
        "export.go",
        "metrics.go",
        "otel.go",
        "test_reporter.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/telemetry",
    visibility = ["//devx:__subpackages__"],
)

go_test(
    name = "telemetry_test",
    srcs = [
        "export_test.go",
        "metrics_test.go",
    ],
    embed = [":telemetry"],
)
