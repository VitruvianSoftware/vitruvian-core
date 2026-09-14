load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "cloudflare",
    srcs = [
        "client.go",
        "dns.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/cloudflare",
    visibility = ["//apps/cli/devx:__subpackages__"],
)
