load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "provider",
    srcs = [
        "colima.go",
        "detect.go",
        "docker.go",
        "lima.go",
        "podman.go",
        "provider.go",
        "registry.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/provider",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
    deps = ["//apps/cli/vitruvian-devx/internal/config"],
)

go_test(
    name = "provider_test",
    srcs = [
        "colima_test.go",
        "detect_test.go",
        "lima_test.go",
        "registry_test.go",
    ],
    embed = [":provider"],
)
