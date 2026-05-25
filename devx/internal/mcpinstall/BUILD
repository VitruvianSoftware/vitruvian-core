load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "mcpinstall",
    srcs = [
        "host.go",
        "host_codex.go",
        "host_json.go",
        "host_manual.go",
        "registry.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/mcpinstall",
    visibility = ["//devx:__subpackages__"],
    deps = ["@com_github_pelletier_go_toml_v2//:go-toml"],
)

go_test(
    name = "mcpinstall_test",
    srcs = [
        "host_codex_test.go",
        "host_json_test.go",
        "host_manual_test.go",
        "registry_test.go",
    ],
    embed = [":mcpinstall"],
    deps = ["@com_github_pelletier_go_toml_v2//:go-toml"],
)
