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
    importpath = "github.com/VitruvianSoftware/devx/internal/provider",
    visibility = ["//devx:__subpackages__"],
    deps = ["//devx/internal/config"],
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
    tags = ["manual"],  # requires docker/podman/colima/lima binaries on PATH; not available in Bazel sandbox
)
