load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "cluster",
    srcs = [
        "advanced.go",
        "apply.go",
        "cluster.go",
        "lock.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/cluster",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
    deps = [
        "//apps/cli/vitruvian-devx/internal/multinode/config",
        "//apps/cli/vitruvian-devx/internal/multinode/k3s",
        "//apps/cli/vitruvian-devx/internal/multinode/lima",
        "//apps/cli/vitruvian-devx/internal/multinode/prereqs",
        "//apps/cli/vitruvian-devx/internal/multinode/provider",
        "//apps/cli/vitruvian-devx/internal/multinode/util",
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
        "//apps/cli/vitruvian-devx/internal/multinode/config",
        "//apps/cli/vitruvian-devx/internal/multinode/lima",
        "//apps/cli/vitruvian-devx/internal/multinode/provider",
    ],
)
