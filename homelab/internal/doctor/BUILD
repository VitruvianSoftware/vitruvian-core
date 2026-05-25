load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "doctor",
    srcs = ["doctor.go"],
    importpath = "github.com/VitruvianSoftware/homelab/internal/doctor",
    visibility = ["//homelab:__subpackages__"],
    deps = [
        "//homelab/internal/config",
        "//homelab/internal/k3s",
        "//homelab/internal/lima",
        "//homelab/internal/remote",
    ],
)
