load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "cluster",
    srcs = [
        "advanced.go",
        "apply.go",
        "cluster.go",
    ],
    importpath = "github.com/VitruvianSoftware/homelab/internal/cluster",
    visibility = ["//homelab:__subpackages__"],
    deps = [
        "//homelab/internal/config",
        "//homelab/internal/k3s",
        "//homelab/internal/lima",
        "//homelab/internal/prereqs",
        "//homelab/internal/remote",
        "@org_golang_x_sync//errgroup",
    ],
)
