load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "tui",
    srcs = [
        "setup.go",
        "styles.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/tui",
    visibility = ["//devx:__subpackages__"],
    deps = [
        "@com_github_charmbracelet_bubbles//spinner",
        "@com_github_charmbracelet_bubbletea//:bubbletea",
        "@com_github_charmbracelet_lipgloss//:lipgloss",
    ],
)
