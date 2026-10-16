load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "sqlite",
    srcs = ["open.go"],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/sqlite",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
    deps = [
        "@fi_mau_go_util//dbutil",
        "@fi_mau_go_util//dbutil/litestream",
    ],
)

go_test(
    name = "sqlite_test",
    srcs = ["open_test.go"],
    embed = [":sqlite"],
    deps = ["@com_github_stretchr_testify//require"],
)
