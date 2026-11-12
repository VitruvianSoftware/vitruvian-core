load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "storetest",
    testonly = True,
    srcs = ["seed.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-courier/engine/internal/store/storetest",
    visibility = ["//apps/desktop/vitruvian-courier/engine:__subpackages__"],
    deps = [
        "//apps/desktop/vitruvian-courier/engine/internal/sqlite",
        "@com_github_stretchr_testify//require",
    ],
)
