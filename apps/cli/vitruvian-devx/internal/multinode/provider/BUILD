load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "provider",
    srcs = [
        "lima.go",
        "native.go",
        "provider.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/provider",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
    deps = [
        "//apps/cli/vitruvian-devx/internal/multinode/config",
        "//apps/cli/vitruvian-devx/internal/multinode/k3s",
        "//apps/cli/vitruvian-devx/internal/multinode/lima",
        "//apps/cli/vitruvian-devx/internal/multinode/remote",
        "//apps/cli/vitruvian-devx/internal/multinode/util",
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
    deps = ["//apps/cli/vitruvian-devx/internal/multinode/config"],
)
