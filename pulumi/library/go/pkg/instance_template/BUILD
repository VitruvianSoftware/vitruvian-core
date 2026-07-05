load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/instance_template

go_library(
    name = "instance_template",
    srcs = [
        "instance_template.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/instance_template",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/compute",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "instance_template_test",
    srcs = [
        "instance_template_test.go",
    ],
    embed = [
        ":instance_template",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//require",
    ],
)
