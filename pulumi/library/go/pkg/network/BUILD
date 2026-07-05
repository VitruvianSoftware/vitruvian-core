load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/network

go_library(
    name = "network",
    srcs = [
        "dns.go",
        "firewall.go",
        "hierarchical_firewall.go",
        "networking.go",
        "psc.go",
        "router.go",
        "transitivity.go",
        "vpn_ha.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/network",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/compute",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/dns",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/projects",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/serviceaccount",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/servicenetworking",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "network_test",
    srcs = [
        "dns_test.go",
        "firewall_test.go",
        "hierarchical_firewall_test.go",
        "networking_test.go",
        "psc_test.go",
        "router_test.go",
        "vpn_ha_test.go",
    ],
    embed = [
        ":network",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil:testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/common/resource",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//assert",
        "@com_github_stretchr_testify//require",
    ],
)
