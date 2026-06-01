load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "cluster",
    srcs = [
        "advanced.go",
        "apply.go",
        "cluster.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/multinode/cluster",
    visibility = ["//devx:__subpackages__"],
    deps = [
        "//devx/internal/multinode/config",
        "//devx/internal/multinode/k3s",
        "//devx/internal/multinode/lima",
        "//devx/internal/multinode/prereqs",
        "//devx/internal/multinode/util",
        "@org_golang_x_sync//errgroup",
    ],
)

go_test(
    name = "cluster_test",
    srcs = ["cluster_reconcile_test.go"],
    embed = [":cluster"],
    deps = [
        "//devx/internal/multinode/config",
        "//devx/internal/multinode/lima",
    ],
)
