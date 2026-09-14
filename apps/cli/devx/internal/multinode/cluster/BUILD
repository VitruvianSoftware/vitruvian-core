load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "cluster",
    srcs = [
        "advanced.go",
        "apply.go",
        "cluster.go",
        "lock.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/multinode/cluster",
    visibility = ["//apps/cli/devx:__subpackages__"],
    deps = [
        "//apps/cli/devx/internal/multinode/config",
        "//apps/cli/devx/internal/multinode/k3s",
        "//apps/cli/devx/internal/multinode/lima",
        "//apps/cli/devx/internal/multinode/prereqs",
        "//apps/cli/devx/internal/multinode/provider",
        "//apps/cli/devx/internal/multinode/util",
        "@org_golang_x_sync//errgroup",
    ],
)

go_test(
    name = "cluster_test",
    srcs = [
        "apply_hardening_test.go",
        "cluster_reconcile_test.go",
        "lock_test.go",
        "reconcile_dispatch_test.go",
    ],
    embed = [":cluster"],
    deps = [
        "//apps/cli/devx/internal/multinode/config",
        "//apps/cli/devx/internal/multinode/lima",
        "//apps/cli/devx/internal/multinode/provider",
    ],
)
