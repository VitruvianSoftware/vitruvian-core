load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/cai_monitoring

go_library(
    name = "cai_monitoring",
    srcs = [
        "cai_monitoring.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/cai_monitoring",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/artifactregistry",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/cloudasset",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/cloudfunctionsv2",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/organizations",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/projects",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/pubsub",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/securitycenter",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/serviceaccount",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/storage",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "cai_monitoring_test",
    srcs = [
        "cai_monitoring_test.go",
    ],
    embed = [
        ":cai_monitoring",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil:testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//assert",
        "@com_github_stretchr_testify//require",
    ],
)
