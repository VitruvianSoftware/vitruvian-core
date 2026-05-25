load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "webhook",
    srcs = [
        "server.go",
        "tui.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/webhook",
    visibility = ["//devx:__subpackages__"],
    deps = [
        "@com_github_charmbracelet_bubbles//viewport",
        "@com_github_charmbracelet_bubbletea//:bubbletea",
        "@com_github_charmbracelet_lipgloss//:lipgloss",
    ],
)
