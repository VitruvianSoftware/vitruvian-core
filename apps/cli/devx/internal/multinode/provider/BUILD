load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "provider",
    srcs = [
        "lima.go",
        "native.go",
        "provider.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/multinode/provider",
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
    name = "provider_test",
    srcs = [
        "native_loud_test.go",
        "native_test.go",
        "provider_test.go",
        "spec_test.go",
    ],
    embed = [":provider"],
    deps = ["//apps/cli/devx/internal/multinode/config"],
)
