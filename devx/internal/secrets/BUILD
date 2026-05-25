load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "secrets",
    srcs = ["loader.go"],
    importpath = "github.com/VitruvianSoftware/devx/internal/secrets",
    visibility = ["//devx:__subpackages__"],
    deps = [
        "@com_github_charmbracelet_huh//:huh",
        "@com_github_joho_godotenv//:godotenv",
    ],
)
