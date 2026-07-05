load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/network_firewall_policy

go_library(
    name = "network_firewall_policy",
    srcs = [
        "network_firewall_policy.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/network_firewall_policy",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/compute",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "network_firewall_policy_test",
    srcs = [
        "network_firewall_policy_test.go",
    ],
    embed = [
        ":network_firewall_policy",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//require",
    ],
)
