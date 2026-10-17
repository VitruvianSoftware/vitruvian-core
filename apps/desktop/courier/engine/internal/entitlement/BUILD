load("@rules_go//go:def.bzl", "go_library", "go_test")

go_test(
    name = "entitlement_test",
    srcs = ["entitlement_test.go"],
    embed = [":entitlement"],
    deps = ["@com_github_stretchr_testify//require"],
)

go_library(
    name = "entitlement",
    srcs = ["entitlement.go"],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/entitlement",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
)
