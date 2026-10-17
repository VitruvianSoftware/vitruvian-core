load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "store",
    srcs = [
        "inbox.go",
        "migrate.go",
        "store.go",
    ],
    embedsrcs = ["schema.sql"],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/store",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
    deps = [
        "//apps/desktop/courier/engine/internal/ids",
        "//apps/desktop/courier/engine/internal/sqlite",
        "@fi_mau_go_util//dbutil",
    ],
)

go_test(
    name = "store_test",
    srcs = [
        "inbox_test.go",
        "store_test.go",
    ],
    data = glob(["testdata/**"]),
    embed = [":store"],
    deps = [
        "//apps/desktop/courier/engine/internal/sqlite",
        "@com_github_stretchr_testify//require",
    ],
)
