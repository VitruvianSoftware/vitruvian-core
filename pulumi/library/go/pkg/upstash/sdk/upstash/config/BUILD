load("@rules_go//go:def.bzl", "go_library")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/upstash/sdk/upstash/config

go_library(
    name = "config",
    srcs = glob(["*.go"]),
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/upstash/sdk/upstash/config",
    visibility = ["//visibility:public"],
    deps = [
        "//pulumi/library/go/pkg/upstash/sdk/upstash/internal",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi/config",
    ],
)
