load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/neon

go_library(
    name = "neon",
    srcs = ["neon.go"],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/neon",
    visibility = ["//visibility:public"],
    deps = [
        "//pulumi/library/go/pkg/neon/sdk/neon",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "neon_test",
    srcs = ["neon_test.go"],
    embed = [":neon"],
    deps = [
        "@com_github_pulumi_pulumi_sdk_v3//go/common/resource",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)
