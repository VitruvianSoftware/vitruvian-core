load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/cloud_run

go_library(
    name = "cloud_run",
    srcs = [
        "cloud_run.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/cloud_run",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/cloudrunv2",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "cloud_run_test",
    srcs = [
        "cloud_run_test.go",
    ],
    embed = [
        ":cloud_run",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//require",
    ],
)
