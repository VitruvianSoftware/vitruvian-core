load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")

go_library(
    name = "courier-engine_lib",
    srcs = ["main.go"],
    importpath = "github.com/VitruvianSoftware/courier/engine/cmd/courier-engine",
    visibility = ["//visibility:private"],
    deps = [
        "//apps/desktop/courier/engine/internal/actions",
        "//apps/desktop/courier/engine/internal/datadir",
        "//apps/desktop/courier/engine/internal/login",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/networks",
        "//apps/desktop/courier/engine/internal/rpc",
        "//apps/desktop/courier/engine/internal/sqlite",
        "//apps/desktop/courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
    ],
)

go_binary(
    name = "courier-engine",
    embed = [":courier-engine_lib"],
    visibility = ["//apps/desktop/courier:__subpackages__"],
)

go_test(
    name = "courier-engine_test",
    srcs = ["main_test.go"],
    # The tests run the real binary, found in the runfiles.
    data = [":courier-engine"],
    embed = [":courier-engine_lib"],
    env = {"COURIER_ENGINE_BIN": "$(rlocationpath :courier-engine)"},
    deps = [
        "//apps/desktop/courier/engine/internal/datadir",
        "@com_github_stretchr_testify//require",
    ],
)
