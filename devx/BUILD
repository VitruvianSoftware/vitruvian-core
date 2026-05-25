load("@rules_go//go:def.bzl", "go_binary", "go_library")

# gazelle:prefix github.com/VitruvianSoftware/devx
# gazelle:exclude docs
# gazelle:exclude scripts
# gazelle:exclude .agents
# gazelle:exclude .github
# gazelle:exclude internal/scaffold/templates/node-api
# gazelle:exclude internal/scaffold/templates/next-app
# gazelle:exclude internal/scaffold/templates/python-api

go_library(
    name = "devx_lib",
    srcs = ["main.go"],
    importpath = "github.com/VitruvianSoftware/devx",
    visibility = ["//visibility:private"],
    deps = ["//devx/cmd"],
)

go_binary(
    name = "devx",
    embed = [":devx_lib"],
    visibility = ["//visibility:public"],
)
