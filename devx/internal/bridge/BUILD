load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "bridge",
    srcs = [
        "agent.go",
        "env.go",
        "intercept.go",
        "kube.go",
        "portforward.go",
        "session.go",
        "tunnel.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/bridge",
    visibility = ["//devx:__subpackages__"],
    deps = [
        "//devx/internal/devxerr",
        "//devx/internal/network",
        "@com_github_hashicorp_yamux//:yamux",
    ],
)

go_test(
    name = "bridge_test",
    srcs = [
        "agent_test.go",
        "intercept_test.go",
        "portforward_test.go",
        "session_test.go",
        "tunnel_test.go",
    ],
    embed = [":bridge"],
)
