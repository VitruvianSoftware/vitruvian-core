load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "testutil",
    srcs = [
        "mocks.go",
    ],
    importpath = "github.com/VitruvianSoftware/pulumi-library/go/internal/testutil",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_pulumi_pulumi_sdk_v3//go/common/resource",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//assert",
        "@com_github_stretchr_testify//require",
    ],
)

go_test(
    name = "testutil_test",
    srcs = [
        "mocks_test.go",
    ],
    embed = [
        ":testutil",
    ],
    deps = [
        "@com_github_pulumi_pulumi_sdk_v3//go/common/resource",
        "@com_github_pulumi_pulumi_sdk_v3//go/pulumi",
        "@com_github_stretchr_testify//assert",
        "@com_github_stretchr_testify//require",
    ],
)
