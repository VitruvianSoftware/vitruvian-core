load("@rules_go//go:def.bzl", "go_library", "go_test")

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

go_test(
    name = "doctor_test",
    srcs = ["bridged_ip_test.go"],
    embed = [":doctor"],
)
