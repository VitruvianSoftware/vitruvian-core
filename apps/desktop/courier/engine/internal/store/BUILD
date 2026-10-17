load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "store",
    srcs = [
        "chatstate.go",
        "inbox.go",
        "labels.go",
        "migrate.go",
        "spaces.go",
        "store.go",
        "typing.go",
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
        "chatstate_test.go",
        "inbox_test.go",
        "labels_test.go",
        "spaces_test.go",
        "store_test.go",
    ],
    data = glob(["testdata/**"]),
    embed = [":store"],
    deps = [
        "//apps/desktop/courier/engine/internal/sqlite",
        "@com_github_stretchr_testify//require",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//event",
    ],
)
