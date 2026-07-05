load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/cloud_router

go_library(
    name = "cloud_router",
    srcs = [
        "cloud_router.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/cloud_router",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/compute",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "cloud_router_test",
    srcs = [
        "cloud_router_test.go",
    ],
    embed = [
        ":cloud_router",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil:testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//require",
    ],
)
