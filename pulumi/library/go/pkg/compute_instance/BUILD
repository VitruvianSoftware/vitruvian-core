load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/compute_instance

go_library(
    name = "compute_instance",
    srcs = [
        "compute_instance.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/compute_instance",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/compute",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "compute_instance_test",
    srcs = [
        "compute_instance_test.go",
    ],
    embed = [
        ":compute_instance",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil:testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//require",
    ],
)
