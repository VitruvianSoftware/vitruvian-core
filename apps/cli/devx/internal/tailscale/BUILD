load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "tailscale",
    srcs = ["agent.go"],
    importpath = "github.com/VitruvianSoftware/devx/internal/tailscale",
    visibility = ["//apps/cli/devx:__subpackages__"],
    deps = ["//apps/cli/devx/internal/podman"],
)

go_test(
    name = "tailscale_test",
    srcs = ["agent_test.go"],
    deps = [":tailscale"],
)
