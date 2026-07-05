load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/cloud_functions

go_library(
    name = "cloud_functions",
    srcs = [
        "cloud_functions.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/cloud_functions",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/cloudfunctionsv2",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "cloud_functions_test",
    srcs = [
        "cloud_functions_test.go",
    ],
    embed = [
        ":cloud_functions",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//require",
    ],
)
