load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "preview",
    srcs = ["sandbox.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/preview",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
    deps = [
        "//apps/cli/vitruvian-devx/internal/cloudflare",
        "//apps/cli/vitruvian-devx/internal/exposure",
        "//apps/cli/vitruvian-devx/internal/tui",
    ],
)

go_test(
    name = "preview_test",
    srcs = ["sandbox_test.go"],
    embed = [":preview"],
)
