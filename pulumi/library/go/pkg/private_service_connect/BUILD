load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/private_service_connect

go_library(
    name = "private_service_connect",
    srcs = [
        "private_service_connect.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/private_service_connect",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/compute",
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/dns",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "private_service_connect_test",
    srcs = [
        "private_service_connect_test.go",
    ],
    embed = [
        ":private_service_connect",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//require",
    ],
)
