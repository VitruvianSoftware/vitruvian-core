load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "cmd",
    srcs = [
        "apply.go",
        "backup.go",
        "destroy.go",
        "doctor.go",
        "init.go",
        "join.go",
        "remove.go",
        "root.go",
        "status.go",
        "upgrade.go",
    ],
    importpath = "github.com/VitruvianSoftware/homelab/internal/cmd",
    visibility = ["//apps/cli/homelab:__subpackages__"],
    deps = [
        "//apps/cli/homelab/internal/cluster",
        "//apps/cli/homelab/internal/config",
        "//apps/cli/homelab/internal/doctor",
        "//apps/cli/homelab/internal/logging",
        "@com_github_spf13_cobra//:cobra",
    ],
)
