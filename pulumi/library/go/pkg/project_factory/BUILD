load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory

go_library(
    name = "project_factory",
    srcs = [
        "project.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_command_sdk//go/command/local",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/billing",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/organizations",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/projects",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/resourcemanager",
        "@com_github_pulumi_pulumi_random_sdk_v4//go/random",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "project_factory_test",
    srcs = [
        "project_test.go",
    ],
    embed = [
        ":project_factory",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//assert",
        "@com_github_stretchr_testify//require",
    ],
)
