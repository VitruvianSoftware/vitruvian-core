load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "doctor",
    srcs = ["doctor.go"],
    importpath = "github.com/VitruvianSoftware/homelab/internal/doctor",
    visibility = ["//apps/cli/homelab:__subpackages__"],
    deps = [
        "//apps/cli/homelab/internal/config",
        "//apps/cli/homelab/internal/k3s",
        "//apps/cli/homelab/internal/lima",
        "//apps/cli/homelab/internal/remote",
    ],
)
