load("@rules_go//go:def.bzl", "go_library")

exports_files(["protocol_gen.go"])

go_library(
    name = "toolkit",
    srcs = ["protocol_gen.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-sdk/go/toolkit",
    visibility = ["//visibility:public"],
)
