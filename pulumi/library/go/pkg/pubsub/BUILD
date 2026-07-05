load("@rules_go//go:def.bzl", "go_library", "go_test")

# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go/pkg/pubsub

go_library(
    name = "pubsub",
    srcs = [
        "pubsub.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/pkg/pubsub",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_gcp_sdk_v9//go/gcp/pubsub",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
    ],
)

go_test(
    name = "pubsub_test",
    srcs = [
        "pubsub_test.go",
    ],
    embed = [
        ":pubsub",
    ],
    deps = [
        "//pulumi/library/go/internal/testutil",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//require",
    ],
)
