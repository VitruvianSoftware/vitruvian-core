load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "doctor",
    srcs = ["doctor.go"],
    importpath = "github.com/VitruvianSoftware/devx/internal/multinode/doctor",
    visibility = ["//apps/cli/devx:__subpackages__"],
    deps = [
        "//apps/cli/devx/internal/multinode/config",
        "//apps/cli/devx/internal/multinode/k3s",
        "//apps/cli/devx/internal/multinode/lima",
        "//apps/cli/devx/internal/multinode/remote",
        "//apps/cli/devx/internal/multinode/util",
    ],
)

go_test(
    name = "doctor_test",
    srcs = ["bridged_ip_test.go"],
    embed = [":doctor"],
)
