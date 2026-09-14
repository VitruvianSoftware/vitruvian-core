load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "image",
    srcs = [
        "build.go",
        "buildload.go",
        "image.go",
        "push.go",
        "registry.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/image",
    visibility = ["//apps/cli/devx:__subpackages__"],
    deps = ["//apps/cli/devx/internal/provider"],
)

go_test(
    name = "image_test",
    srcs = [
        "build_test.go",
        "buildload_integration_test.go",
        "image_test.go",
        "registry_integration_test.go",
        "registry_test.go",
    ],
    embed = [":image"],
)
