load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")
load("//apps/desktop/courier/app:version.bzl", "COURIER_VERSION")

go_library(
    name = "courier-engine_lib",
    srcs = ["main.go"],
    importpath = "github.com/VitruvianSoftware/courier/engine/cmd/courier-engine",
    visibility = ["//visibility:private"],
    deps = [
        "//apps/desktop/courier/engine/internal/actions",
        "//apps/desktop/courier/engine/internal/datadir",
        "//apps/desktop/courier/engine/internal/engine",
        "//apps/desktop/courier/engine/internal/entitlement",
        "//apps/desktop/courier/engine/internal/login",
        "//apps/desktop/courier/engine/internal/logscrub",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/networks",
        "//apps/desktop/courier/engine/internal/rpc",
        "//apps/desktop/courier/engine/internal/search",
        "//apps/desktop/courier/engine/internal/sqlite",
        "//apps/desktop/courier/engine/internal/store",
        "//apps/desktop/courier/engine/internal/timers",
        "@com_github_rs_zerolog//:zerolog",
    ],
)

go_binary(
    name = "courier-engine",
    embed = [":courier-engine_lib"],
    visibility = ["//apps/desktop/courier:__subpackages__"],
    # hello's engine version: the app's version, from one constant (app/version.bzl).
    x_defs = {"main.version": COURIER_VERSION},
)

go_test(
    name = "courier-engine_test",
    srcs = ["main_test.go"],
    # The tests run the real binary, found in the runfiles.
    data = [":courier-engine"],
    embed = [":courier-engine_lib"],
    env = {
        "COURIER_ENGINE_BIN": "$(rlocationpath :courier-engine)",
        # The version the binary was stamped with, which hello must report.
        "COURIER_ENGINE_VERSION": COURIER_VERSION,
    },
    deps = [
        "//apps/desktop/courier/engine/internal/actions",
        "//apps/desktop/courier/engine/internal/datadir",
        "//apps/desktop/courier/engine/internal/engine",
        "//apps/desktop/courier/engine/internal/entitlement",
        "//apps/desktop/courier/engine/internal/fakenet",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/networks",
        "//apps/desktop/courier/engine/internal/rpc",
        "//apps/desktop/courier/engine/internal/store",
        "//apps/desktop/courier/engine/internal/store/storetest",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
        "@net_maunium_go_mautrix//bridgev2",
    ],
)
