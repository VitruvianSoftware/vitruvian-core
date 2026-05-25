load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "database",
    srcs = [
        "engine.go",
        "query.go",
        "snapshot.go",
        "synthesizer.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/database",
    visibility = ["//devx:__subpackages__"],
    deps = [
        "//devx/internal/provider",
        "@com_github_charmbracelet_lipgloss//:lipgloss",
    ],
)

go_test(
    name = "database_test",
    srcs = [
        "engine_test.go",
        "query_test.go",
        "synthesizer_test.go",
    ],
    embed = [":database"],
)
