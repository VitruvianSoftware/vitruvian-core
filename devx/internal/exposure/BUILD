load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "exposure",
    srcs = [
        "domain.go",
        "store.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/exposure",
    visibility = ["//devx:__subpackages__"],
)

go_test(
    name = "exposure_test",
    srcs = ["domain_test.go"],
    embed = [":exposure"],
)
