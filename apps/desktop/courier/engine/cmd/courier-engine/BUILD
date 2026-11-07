load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")
load("//apps/desktop/courier/app:version.bzl", "COURIER_VERSION")

# seed_on.go (and seed_e2e_test.go) build only with the courierseed tag; Gazelle lists them, and their deps, beside
# the untagged files, and rules_go leaves them out of every build without the tag.
# gazelle:build_tags courierseed

go_library(
    name = "courier-engine_lib",
    srcs = [
        "main.go",
        "mcpstdio.go",
        "seed_off.go",
        "seed_on.go",
    ],
    importpath = "github.com/VitruvianSoftware/courier/engine/cmd/courier-engine",
    visibility = ["//visibility:private"],
    deps = [
        "//apps/desktop/courier/engine/internal/actions",
        "//apps/desktop/courier/engine/internal/datadir",
        "//apps/desktop/courier/engine/internal/engine",
        "//apps/desktop/courier/engine/internal/entitlement",
        "//apps/desktop/courier/engine/internal/fakenet",
        "//apps/desktop/courier/engine/internal/ids",
        "//apps/desktop/courier/engine/internal/localapi",
        "//apps/desktop/courier/engine/internal/login",
        "//apps/desktop/courier/engine/internal/logscrub",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/networks",
        "//apps/desktop/courier/engine/internal/rpc",
        "//apps/desktop/courier/engine/internal/search",
        "//apps/desktop/courier/engine/internal/seed",
        "//apps/desktop/courier/engine/internal/sqlite",
        "//apps/desktop/courier/engine/internal/store",
        "//apps/desktop/courier/engine/internal/timers",
        "@com_github_modelcontextprotocol_go_sdk//mcp",
        "@com_github_rs_zerolog//:zerolog",
        "@net_maunium_go_mautrix//bridgev2",
    ],
)

go_binary(
    name = "courier-engine",
    embed = [":courier-engine_lib"],
    visibility = ["//apps/desktop/courier:__subpackages__"],
    # hello's engine version: the app's version, from one constant (app/version.bzl).
    x_defs = {"main.version": COURIER_VERSION},
)

# The test copy's engine: the same program built with the courierseed tag, so COURIER_SEED can fill it with a
# made-up scenario (seed_on.go, //apps/desktop/courier/seed). Only :CourierTestCopy bundles it; the released app's
# engine is :courier-engine, which links no seed code (the app's release_engine_has_no_seed_test checks both).
go_binary(
    name = "courier-engine-seeded",
    embed = [":courier-engine_lib"],
    gotags = ["courierseed"],
    visibility = ["//apps/desktop/courier:__subpackages__"],
    x_defs = {"main.version": COURIER_VERSION},
)

go_test(
    name = "courier-engine_test",
    srcs = [
        "main_test.go",
        "mcpstdio_test.go",
        "seed_e2e_test.go",
    ],
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
        "//apps/desktop/courier/engine/internal/localapi",
        "//apps/desktop/courier/engine/internal/logscrub",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/networks",
        "//apps/desktop/courier/engine/internal/rpc",
        "//apps/desktop/courier/engine/internal/seed",
        "//apps/desktop/courier/engine/internal/store",
        "//apps/desktop/courier/engine/internal/store/storetest",
        "@com_github_modelcontextprotocol_go_sdk//mcp",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
        "@net_maunium_go_mautrix//bridgev2",
    ],
)

# The seeded engine end to end (seed_e2e_test.go): it plays a scenario into an empty data folder, and only once.
# Built with the courierseed tag, against the seeded binary; only its seed tests run (main_test.go is its harness).
go_test(
    name = "courier-engine_seed_test",
    srcs = [
        "main_test.go",
        "mcpstdio_test.go",
        "seed_e2e_test.go",
    ],
    args = ["-test.run=^TestSeed"],
    data = [
        ":courier-engine-seeded",
        "//apps/desktop/courier/seed:scenarios",
    ],
    embed = [":courier-engine_lib"],
    env = {
        "COURIER_ENGINE_BIN": "$(rlocationpath :courier-engine-seeded)",
        "COURIER_ENGINE_VERSION": COURIER_VERSION,
        "COURIER_SEED_SCENARIOS": "$(rlocationpaths //apps/desktop/courier/seed:scenarios)",
    },
    gotags = ["courierseed"],
    deps = [
        "//apps/desktop/courier/engine/internal/actions",
        "//apps/desktop/courier/engine/internal/datadir",
        "//apps/desktop/courier/engine/internal/engine",
        "//apps/desktop/courier/engine/internal/entitlement",
        "//apps/desktop/courier/engine/internal/fakenet",
        "//apps/desktop/courier/engine/internal/localapi",
        "//apps/desktop/courier/engine/internal/logscrub",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/networks",
        "//apps/desktop/courier/engine/internal/rpc",
        "//apps/desktop/courier/engine/internal/seed",
        "//apps/desktop/courier/engine/internal/store",
        "//apps/desktop/courier/engine/internal/store/storetest",
        "@com_github_modelcontextprotocol_go_sdk//mcp",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
        "@net_maunium_go_mautrix//bridgev2",
    ],
)
