load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/network_peering

go_library(
    name = "network_peering",
    srcs = [
        "network_peering.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/network_peering",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/compute",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "network_peering_test",
    srcs = [
        "network_peering_test.go",
    ],
    embed = [
        ":network_peering",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil:testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//require",
    ],
)
