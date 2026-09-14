load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "prereqs",
    srcs = ["prereqs.go"],
    importpath = "github.com/VitruvianSoftware/devx/internal/multinode/prereqs",
    visibility = ["//apps/cli/devx:__subpackages__"],
    deps = [
        "//apps/cli/devx/internal/multinode/config",
        "//apps/cli/devx/internal/multinode/remote",
        "//apps/cli/devx/internal/multinode/util",
    ],
)

go_test(
    name = "prereqs_test",
    srcs = ["prereqs_test.go"],
    embed = [":prereqs"],
)
