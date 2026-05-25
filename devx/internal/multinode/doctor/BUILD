load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "doctor",
    srcs = ["doctor.go"],
    importpath = "github.com/VitruvianSoftware/devx/internal/multinode/doctor",
    visibility = ["//devx:__subpackages__"],
    deps = [
        "//devx/internal/multinode/config",
        "//devx/internal/multinode/k3s",
        "//devx/internal/multinode/lima",
        "//devx/internal/multinode/remote",
        "//devx/internal/multinode/util",
    ],
)
