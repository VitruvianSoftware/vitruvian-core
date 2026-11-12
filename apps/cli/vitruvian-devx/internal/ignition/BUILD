load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "ignition",
    srcs = [
        "builder.go",
        "deploy.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/ignition",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
    deps = ["//apps/cli/vitruvian-devx/internal/podman"],
)

go_test(
    name = "ignition_test",
    srcs = ["builder_test.go"],
    deps = [":ignition"],
)
