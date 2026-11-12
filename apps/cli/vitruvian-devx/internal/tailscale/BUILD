load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "tailscale",
    srcs = ["agent.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/tailscale",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
    deps = ["//apps/cli/vitruvian-devx/internal/podman"],
)

go_test(
    name = "tailscale_test",
    srcs = ["agent_test.go"],
    deps = [":tailscale"],
)
