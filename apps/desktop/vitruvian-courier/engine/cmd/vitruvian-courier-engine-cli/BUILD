load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")

go_library(
    name = "vitruvian-courier-engine-cli_lib",
    srcs = [
        "login.go",
        "main.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-courier/engine/cmd/vitruvian-courier-engine-cli",
    visibility = ["//visibility:private"],
    deps = [
        "//apps/desktop/vitruvian-courier/engine/internal/actions",
        "//apps/desktop/vitruvian-courier/engine/internal/datadir",
        "//apps/desktop/vitruvian-courier/engine/internal/engine",
        "//apps/desktop/vitruvian-courier/engine/internal/host",
        "//apps/desktop/vitruvian-courier/engine/internal/login",
        "//apps/desktop/vitruvian-courier/engine/internal/logscrub",
        "//apps/desktop/vitruvian-courier/engine/internal/media",
        "//apps/desktop/vitruvian-courier/engine/internal/networks",
        "//apps/desktop/vitruvian-courier/engine/internal/sqlite",
        "//apps/desktop/vitruvian-courier/engine/internal/store",
        "@com_github_mdp_qrterminal_v3//:qrterminal",
        "@com_github_rs_zerolog//:zerolog",
        "@fi_mau_go_util//curl",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//event",
        "@org_golang_x_term//:term",
    ],
)

go_binary(
    name = "vitruvian-courier-engine-cli",
    embed = [":vitruvian-courier-engine-cli_lib"],
    visibility = ["//apps/desktop/vitruvian-courier:__subpackages__"],
)

go_test(
    name = "vitruvian-courier-engine-cli_test",
    srcs = [
        "login_test.go",
        "main_test.go",
    ],
    embed = [":vitruvian-courier-engine-cli_lib"],
    deps = [
        "//apps/desktop/vitruvian-courier/engine/internal/engine",
        "//apps/desktop/vitruvian-courier/engine/internal/fakenet",
        "//apps/desktop/vitruvian-courier/engine/internal/host",
        "//apps/desktop/vitruvian-courier/engine/internal/media",
        "//apps/desktop/vitruvian-courier/engine/internal/networks",
        "//apps/desktop/vitruvian-courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
        "@net_maunium_go_mautrix//bridgev2",
    ],
)
