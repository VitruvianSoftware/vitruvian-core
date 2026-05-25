load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "devxerr",
    srcs = [
        "error.go",
        "recovery.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/devxerr",
    visibility = ["//devx:__subpackages__"],
    deps = ["@com_github_charmbracelet_huh//:huh"],
)
