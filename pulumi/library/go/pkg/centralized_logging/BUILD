load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/centralized_logging

go_library(
    name = "centralized_logging",
    srcs = [
        "centralized_logging.go",
        "log_export.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/centralized_logging",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/logging",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/projects",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/pubsub",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/storage",
        "@com_github_pulumi_pulumi_random_sdk_v4//go/random",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "centralized_logging_test",
    srcs = [
        "centralized_logging_test.go",
        "log_export_test.go",
    ],
    embed = [
        ":centralized_logging",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/common/resource",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//assert",
        "@com_github_stretchr_testify//require",
    ],
)
