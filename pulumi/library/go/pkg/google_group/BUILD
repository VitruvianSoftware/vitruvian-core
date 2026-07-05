load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/google_group

go_library(
    name = "google_group",
    srcs = [
        "group.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/google_group",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/cloudidentity",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "google_group_test",
    srcs = [
        "group_test.go",
    ],
    embed = [
        ":google_group",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//assert",
        "@com_github_stretchr_testify//require",
    ],
)
