load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "preview",
    srcs = ["sandbox.go"],
    importpath = "github.com/VitruvianSoftware/devx/internal/preview",
    visibility = ["//devx:__subpackages__"],
    deps = [
        "//devx/internal/cloudflare",
        "//devx/internal/exposure",
        "//devx/internal/tui",
    ],
)

go_test(
    name = "preview_test",
    srcs = ["sandbox_test.go"],
    embed = [":preview"],
)
