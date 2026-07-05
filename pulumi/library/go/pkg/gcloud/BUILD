load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/gcloud

go_library(
    name = "gcloud",
    srcs = [
        "gcloud.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/gcloud",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_command_sdk//go/command/local",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "gcloud_test",
    srcs = [
        "gcloud_test.go",
    ],
    embed = [
        ":gcloud",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil:testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//require",
    ],
)
