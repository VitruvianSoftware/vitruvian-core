load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/vpc_service_controls

go_library(
    name = "vpc_service_controls",
    srcs = [
        "vpc_sc.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/vpc_service_controls",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/accesscontextmanager",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "vpc_service_controls_test",
    srcs = [
        "vpc_sc_test.go",
    ],
    embed = [
        ":vpc_service_controls",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/accesscontextmanager",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//require",
    ],
)
