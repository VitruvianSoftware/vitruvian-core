load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "inspector",
    srcs = [
        "capture.go",
        "proxy.go",
        "tui.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/inspector",
    visibility = ["//devx:__subpackages__"],
    deps = [
        "@com_github_charmbracelet_bubbletea//:bubbletea",
        "@com_github_charmbracelet_lipgloss//:lipgloss",
    ],
)

go_test(
    name = "inspector_test",
    srcs = [
        "e2e_test.go",
        "proxy_test.go",
    ],
    embed = [":inspector"],
)
