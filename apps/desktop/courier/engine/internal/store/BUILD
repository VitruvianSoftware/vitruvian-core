load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "store",
    srcs = ["store.go"],
    embedsrcs = ["schema.sql"],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/store",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
    deps = [
        "//apps/desktop/courier/engine/internal/sqlite",
        "@fi_mau_go_util//dbutil",
    ],
)

go_test(
    name = "store_test",
    srcs = ["store_test.go"],
    embed = [":store"],
    deps = ["@com_github_stretchr_testify//require"],
)
