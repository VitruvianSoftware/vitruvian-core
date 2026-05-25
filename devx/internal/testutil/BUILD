load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "testutil",
    srcs = ["fake_runtime.go"],
    importpath = "github.com/VitruvianSoftware/devx/internal/testutil",
    visibility = ["//devx:__subpackages__"],
    deps = ["//devx/internal/secrets"],
)
