load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "storetest",
    testonly = True,
    srcs = ["seed.go"],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/store/storetest",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
    deps = [
        "//apps/desktop/courier/engine/internal/sqlite",
        "@com_github_stretchr_testify//require",
    ],
)
