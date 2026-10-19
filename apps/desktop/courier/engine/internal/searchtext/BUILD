load("@rules_go//go:def.bzl", "go_library", "go_test")

go_test(
    name = "searchtext_test",
    srcs = [
        "fuzz_test.go",
        "searchtext_test.go",
    ],
    data = glob(["testdata/**"]),
    embed = [":searchtext"],
    deps = [
        "//apps/desktop/courier/engine/internal/sqlite",
        "@com_github_stretchr_testify//assert",
        "@com_github_stretchr_testify//require",
        "@fi_mau_go_util//dbutil",
    ],
)

# The seed corpus of strange queries. The store's tests read the same file as data (Review Focus 2).
filegroup(
    name = "queries",
    srcs = ["testdata/queries.txt"],
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
)

go_library(
    name = "searchtext",
    srcs = ["searchtext.go"],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/searchtext",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
    deps = ["@org_golang_x_text//unicode/norm"],
)
