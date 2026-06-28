load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "provider",
    srcs = [
        "lima.go",
        "native.go",
        "provider.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/multinode/provider",
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
    name = "provider_test",
    srcs = [
        "native_loud_test.go",
        "native_test.go",
        "provider_test.go",
    ],
    embed = [":provider"],
    deps = ["//devx/internal/multinode/config"],
)
