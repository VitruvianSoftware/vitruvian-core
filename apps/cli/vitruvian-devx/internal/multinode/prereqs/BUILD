load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "prereqs",
    srcs = ["prereqs.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/prereqs",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
    deps = [
        "//apps/cli/vitruvian-devx/internal/multinode/config",
        "//apps/cli/vitruvian-devx/internal/multinode/remote",
        "//apps/cli/vitruvian-devx/internal/multinode/util",
    ],
)

go_test(
    name = "prereqs_test",
    srcs = ["prereqs_test.go"],
    embed = [":prereqs"],
)
