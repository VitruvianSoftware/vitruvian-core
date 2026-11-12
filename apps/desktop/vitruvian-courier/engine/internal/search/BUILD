load("@rules_go//go:def.bzl", "go_library", "go_test")

go_test(
    name = "search_test",
    srcs = [
        "backfill_test.go",
        "search_test.go",
    ],
    embed = [":search"],
    deps = [
        "//apps/desktop/vitruvian-courier/engine/internal/ids",
        "//apps/desktop/vitruvian-courier/engine/internal/store",
        "//apps/desktop/vitruvian-courier/engine/internal/store/storetest",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
    ],
)

go_library(
    name = "search",
    srcs = [
        "backfill.go",
        "search.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-courier/engine/internal/search",
    visibility = ["//apps/desktop/vitruvian-courier/engine:__subpackages__"],
    deps = [
        "//apps/desktop/vitruvian-courier/engine/internal/searchtext",
        "//apps/desktop/vitruvian-courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
    ],
)
