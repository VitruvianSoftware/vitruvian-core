load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "datadir",
    srcs = ["lock.go"],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/datadir",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
)

go_test(
    name = "datadir_test",
    srcs = ["lock_test.go"],
    embed = [":datadir"],
    deps = ["@com_github_stretchr_testify//require"],
)
