load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "logs",
    srcs = [
        "color.go",
        "crashlog.go",
        "linewriter.go",
        "redactor.go",
        "sink.go",
        "streamer.go",
        "tui.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/logs",
    visibility = ["//devx:__subpackages__"],
    deps = [
        "//devx/internal/provider",
        "@com_github_charmbracelet_bubbles//viewport",
        "@com_github_charmbracelet_bubbletea//:bubbletea",
        "@com_github_charmbracelet_lipgloss//:lipgloss",
    ],
)

go_test(
    name = "logs_test",
    srcs = [
        "color_test.go",
        "linewriter_test.go",
        "redactor_test.go",
        "sink_test.go",
        "streamer_test.go",
    ],
    embed = [":logs"],
)
