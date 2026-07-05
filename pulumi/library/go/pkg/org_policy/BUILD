load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/org_policy

go_library(
    name = "org_policy",
    srcs = [
        "org_policy.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/org_policy",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/orgpolicy",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "org_policy_test",
    srcs = [
        "org_policy_test.go",
    ],
    embed = [
        ":org_policy",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil:testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//assert",
        "@com_github_stretchr_testify//require",
    ],
)
