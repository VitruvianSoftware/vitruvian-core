load("@rules_go//go:def.bzl", "go_library", "go_test")

exports_files(["protocol_gen.go"])

# The kit's sources as files, for //packages/vitruvian-sdk:go_kit_vet_test,
# which vets them as a module of their own.
filegroup(
    name = "sources",
    srcs = glob(
        ["*.go"],
        exclude = ["*_test.go"],
    ),
    visibility = ["//packages/vitruvian-sdk:__pkg__"],
)

go_library(
    name = "toolkit",
    srcs = [
        "app.go",
        "doc.go",
        "errors.go",
        "link.go",
        "protocol_gen.go",
        "tool.go",
        "version.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-sdk/go/toolkit",
    visibility = ["//visibility:public"],
)

go_test(
    name = "toolkit_test",
    srcs = [
        "protocol_test.go",
        "tool_test.go",
    ],
    data = ["//packages/vitruvian-sdk:protocol_files"],
    embed = [":toolkit"],
)
