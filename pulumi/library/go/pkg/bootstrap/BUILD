load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/bootstrap

go_library(
    name = "bootstrap",
    srcs = [
        "bootstrap.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/bootstrap/v2",
    visibility = ["//visibility:public"],
    deps = [
        "//pulumi/library/go/pkg/project_factory",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/kms",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/projects",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/storage",
        "@com_github_pulumi_pulumi_random_sdk_v4//go/random",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "bootstrap_test",
    srcs = [
        "bootstrap_test.go",
    ],
    embed = [
        ":bootstrap",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//assert",
        "@com_github_stretchr_testify//require",
    ],
)
