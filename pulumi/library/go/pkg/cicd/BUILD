load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/cicd

go_library(
    name = "cicd",
    srcs = [
        "cloudbuild.go",
        "github.go",
        "gitlab.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/cicd",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/artifactregistry",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/cloudbuild",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/iam",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/serviceaccount",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/sourcerepo",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "cicd_test",
    srcs = [
        "cicd_test.go",
        "cloudbuild_test.go",
    ],
    embed = [
        ":cicd",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil:testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//assert",
        "@com_github_stretchr_testify//require",
    ],
)
