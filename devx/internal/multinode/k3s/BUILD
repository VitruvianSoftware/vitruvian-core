load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "k3s",
    srcs = [
        "advanced.go",
        "k3s.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/multinode/k3s",
    visibility = ["//devx:__subpackages__"],
    deps = ["//devx/internal/multinode/remote"],
)

go_test(
    name = "k3s_test",
    srcs = [
        "advanced_test.go",
        "k3s_defaults_test.go",
        "k3s_exec_test.go",
    ],
    embed = [":k3s"],
    deps = ["//devx/internal/multinode/remote"],
)
