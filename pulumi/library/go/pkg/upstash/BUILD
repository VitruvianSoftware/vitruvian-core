load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/upstash

go_library(
    name = "upstash",
    srcs = ["upstash.go"],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/upstash",
    visibility = ["//visibility:public"],
    deps = [
        "//pulumi/library/go/pkg/upstash/sdk/upstash",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "upstash_test",
    srcs = ["upstash_test.go"],
    embed = [":upstash"],
    deps = [
        "@com_github_pulumi_pulumi_sdk_v3//go/common/resource",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)
