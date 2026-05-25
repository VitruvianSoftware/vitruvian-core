load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "mcpserver",
    srcs = [
        "exec.go",
        "server.go",
        "tools.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/mcpserver",
    visibility = ["//devx:__subpackages__"],
    deps = [
        "@com_github_mark3labs_mcp_go//mcp",
        "@com_github_mark3labs_mcp_go//server",
    ],
)

go_test(
    name = "mcpserver_test",
    srcs = [
        "server_test.go",
        "tools_test.go",
    ],
    embed = [":mcpserver"],
)
