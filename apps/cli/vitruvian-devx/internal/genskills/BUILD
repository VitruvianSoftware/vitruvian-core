load("@rules_go//go:def.bzl", "go_binary", "go_library")

go_library(
    name = "genskills_lib",
    srcs = ["main.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/genskills",
    visibility = ["//visibility:private"],
    deps = [
        "//apps/cli/vitruvian-devx/cmd",
        "//apps/cli/vitruvian-devx/internal/agent",
    ],
)

go_binary(
    name = "genskills",
    embed = [":genskills_lib"],
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
)
