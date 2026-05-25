load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "ai",
    srcs = [
        "agent.go",
        "bridge.go",
        "completion.go",
        "diagnose.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/ai",
    visibility = ["//devx:__subpackages__"],
    deps = ["@com_github_charmbracelet_lipgloss//:lipgloss"],
)

go_test(
    name = "ai_test",
    srcs = [
        "completion_test.go",
        "diagnose_test.go",
    ],
    embed = [":ai"],
)
