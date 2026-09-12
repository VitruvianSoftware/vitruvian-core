load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "cluster",
    srcs = [
        "advanced.go",
        "apply.go",
        "cluster.go",
    ],
    importpath = "github.com/VitruvianSoftware/homelab/internal/cluster",
    visibility = ["//apps/cli/homelab:__subpackages__"],
    deps = [
        "//apps/cli/homelab/internal/config",
        "//apps/cli/homelab/internal/k3s",
        "//apps/cli/homelab/internal/lima",
        "//apps/cli/homelab/internal/prereqs",
        "//apps/cli/homelab/internal/remote",
        "@org_golang_x_sync//errgroup",
    ],
)
