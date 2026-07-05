load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/cloud_dns

go_library(
    name = "cloud_dns",
    srcs = [
        "cloud_dns.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/cloud_dns",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/dns",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "cloud_dns_test",
    srcs = [
        "cloud_dns_test.go",
    ],
    embed = [
        ":cloud_dns",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil:testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//require",
    ],
)
