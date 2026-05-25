load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "orchestrator",
    srcs = [
        "bridge_node.go",
        "cloudrun_node.go",
        "container_node.go",
        "dag.go",
        "helm.go",
        "kubernetes_logs.go",
        "kubernetes_node.go",
        "kubernetes_portforward.go",
        "kubernetes_sync.go",
        "logmode.go",
        "output.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/orchestrator",
    visibility = ["//devx:__subpackages__"],
    deps = [
        "//devx/internal/bridge",
        "//devx/internal/image",
        "//devx/internal/logs",
        "//devx/internal/network",
        "//devx/internal/provider",
        "@com_github_google_uuid//:uuid",
    ],
)

go_test(
    name = "orchestrator_test",
    srcs = [
        "bridge_node_test.go",
        "cloudrun_node_test.go",
        "cloudrun_test.go",
        "container_node_test.go",
        "dag_test.go",
        "helm_integration_test.go",
        "helm_test.go",
        "kubernetes_logs_test.go",
        "kubernetes_node_integration_test.go",
        "kubernetes_node_test.go",
        "kubernetes_portforward_integration_test.go",
        "kubernetes_portforward_test.go",
        "kubernetes_sync_integration_test.go",
        "kubernetes_sync_test.go",
        "logmode_test.go",
        "oneshot_test.go",
        "output_test.go",
    ],
    embed = [":orchestrator"],
    deps = ["//devx/internal/image"],
)
