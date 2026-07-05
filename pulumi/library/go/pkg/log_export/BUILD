load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/log_export

go_library(
    name = "log_export",
    srcs = [
        "log_export.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/log_export",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/logging",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "log_export_test",
    srcs = [
        "log_export_test.go",
    ],
    embed = [
        ":log_export",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//require",
    ],
)
