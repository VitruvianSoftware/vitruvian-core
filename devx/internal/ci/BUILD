load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "ci",
    srcs = [
        "executor.go",
        "parser.go",
        "template.go",
        "writer.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/ci",
    visibility = ["//devx:__subpackages__"],
    deps = [
        "//devx/internal/devcontainer",
        "//devx/internal/devxerr",
        "@com_github_charmbracelet_lipgloss//:lipgloss",
        "@in_gopkg_yaml_v3//:yaml_v3",
    ],
)

go_test(
    name = "ci_test",
    srcs = ["parser_test.go"],
    embed = [":ci"],
)
