load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/cloud_storage

go_library(
    name = "cloud_storage",
    srcs = [
        "storage.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/cloud_storage",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/storage",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "cloud_storage_test",
    srcs = [
        "storage_test.go",
    ],
    embed = [
        ":cloud_storage",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil:testutil",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/storage",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//assert",
        "@com_github_stretchr_testify//require",
    ],
)
