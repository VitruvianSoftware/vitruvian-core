load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/iam

go_library(
    name = "iam",
    srcs = [
        "billing.go",
        "folder.go",
        "organization.go",
        "project.go",
        "service_account.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/iam",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/billing",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/folder",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/organizations",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/projects",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/serviceaccount",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "iam_test",
    srcs = [
        "billing_test.go",
        "folder_test.go",
        "organization_test.go",
        "project_test.go",
        "service_account_test.go",
    ],
    embed = [
        ":iam",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil:testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//assert",
        "@com_github_stretchr_testify//require",
    ],
)
