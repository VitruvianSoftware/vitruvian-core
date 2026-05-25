load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "ignition",
    srcs = [
        "builder.go",
        "deploy.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/ignition",
    visibility = ["//devx:__subpackages__"],
    deps = ["//devx/internal/podman"],
)

go_test(
    name = "ignition_test",
    srcs = ["builder_test.go"],
    deps = [":ignition"],
)
