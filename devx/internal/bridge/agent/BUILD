load("@rules_go//go:def.bzl", "go_binary", "go_library")

go_library(
    name = "agent_lib",
    srcs = ["main.go"],
    importpath = "github.com/VitruvianSoftware/devx/internal/bridge/agent",
    visibility = ["//visibility:private"],
    deps = ["@com_github_hashicorp_yamux//:yamux"],
)

go_binary(
    name = "agent",
    embed = [":agent_lib"],
    visibility = ["//devx:__subpackages__"],
)
