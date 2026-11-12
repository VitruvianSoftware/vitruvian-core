load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "logscrub",
    srcs = [
        "logscrub.go",
        "stack.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-courier/engine/internal/logscrub",
    visibility = ["//apps/desktop/vitruvian-courier/engine:__subpackages__"],
)

go_test(
    name = "logscrub_test",
    srcs = [
        "bridge_test.go",
        "logscrub_test.go",
        "stack_test.go",
    ],
    data = ["//apps/desktop/vitruvian-courier/protocol:logscrub_cases"],  # keep
    embed = [":logscrub"],
    deps = [
        "//apps/desktop/vitruvian-courier/engine/internal/actions",
        "//apps/desktop/vitruvian-courier/engine/internal/engine",
        "//apps/desktop/vitruvian-courier/engine/internal/fakenet",
        "//apps/desktop/vitruvian-courier/engine/internal/ids",
        "//apps/desktop/vitruvian-courier/engine/internal/media",
        "//apps/desktop/vitruvian-courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//bridgev2/networkid",
    ],
)
