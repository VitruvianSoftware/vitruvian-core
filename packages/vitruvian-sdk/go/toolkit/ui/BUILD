load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "ui",
    srcs = ["ui.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-sdk/go/toolkit/ui",
    visibility = ["//visibility:public"],
    deps = ["//packages/vitruvian-sdk/go/toolkit"],
)

# The subpackage's sources as files, for //packages/vitruvian-sdk:go_kit_vet_test,
# which vets them with the kit's as a module of their own.
filegroup(
    name = "sources",
    srcs = glob(
        ["*.go"],
        exclude = ["*_test.go"],
    ),
    visibility = ["//packages/vitruvian-sdk:__pkg__"],
)
