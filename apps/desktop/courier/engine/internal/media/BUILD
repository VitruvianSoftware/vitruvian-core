load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "media",
    srcs = ["media.go"],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/media",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
)

go_test(
    name = "media_test",
    srcs = ["media_test.go"],
    embed = [":media"],
    deps = ["@com_github_stretchr_testify//require"],
)
