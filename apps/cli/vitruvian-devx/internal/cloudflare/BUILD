load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "cloudflare",
    srcs = [
        "client.go",
        "dns.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/cloudflare",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
)
