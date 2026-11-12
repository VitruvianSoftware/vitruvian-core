load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "ci",
    srcs = [
        "executor.go",
        "parser.go",
        "template.go",
        "writer.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/ci",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
    deps = [
        "//apps/cli/vitruvian-devx/internal/devcontainer",
        "//apps/cli/vitruvian-devx/internal/devxerr",
        "@com_github_charmbracelet_lipgloss//:lipgloss",
        "@in_gopkg_yaml_v3//:yaml_v3",
    ],
)

go_test(
    name = "ci_test",
    srcs = ["parser_test.go"],
    embed = [":ci"],
)
