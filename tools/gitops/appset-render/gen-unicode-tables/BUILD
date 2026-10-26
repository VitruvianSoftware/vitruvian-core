load("@rules_go//go:def.bzl", "go_binary", "go_library")

go_library(
    name = "gen_unicode_tables_lib",
    srcs = ["main.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/gitops/appset-render/gen-unicode-tables",
    visibility = ["//visibility:private"],
)

go_binary(
    name = "gen-unicode-tables",
    embed = [":gen_unicode_tables_lib"],
    visibility = ["//visibility:public"],
)
