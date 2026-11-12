load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")
load("//apps/desktop/vitruvian-courier/app:version.bzl", "VITRUVIAN_COURIER_VERSION")

# seed_on.go (and seed_e2e_test.go) build only with the courierseed tag; Gazelle lists them, and their deps, beside
# the untagged files, and rules_go leaves them out of every build without the tag.
# gazelle:build_tags courierseed

go_library(
    name = "vitruvian-vitruvian-courier-engine_lib",
    srcs = [
        "main.go",
        "mcpstdio.go",
        "seed_off.go",
        "seed_on.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-courier/engine/cmd/vitruvian-vitruvian-courier-engine",
    visibility = ["//visibility:private"],
    deps = [
        "//apps/desktop/vitruvian-courier/engine/internal/actions",
        "//apps/desktop/vitruvian-courier/engine/internal/datadir",
        "//apps/desktop/vitruvian-courier/engine/internal/engine",
        "//apps/desktop/vitruvian-courier/engine/internal/entitlement",
        "//apps/desktop/vitruvian-courier/engine/internal/fakenet",
        "//apps/desktop/vitruvian-courier/engine/internal/ids",
        "//apps/desktop/vitruvian-courier/engine/internal/localapi",
        "//apps/desktop/vitruvian-courier/engine/internal/login",
        "//apps/desktop/vitruvian-courier/engine/internal/logscrub",
        "//apps/desktop/vitruvian-courier/engine/internal/media",
        "//apps/desktop/vitruvian-courier/engine/internal/networks",
        "//apps/desktop/vitruvian-courier/engine/internal/rpc",
        "//apps/desktop/vitruvian-courier/engine/internal/search",
        "//apps/desktop/vitruvian-courier/engine/internal/seed",
        "//apps/desktop/vitruvian-courier/engine/internal/sqlite",
        "//apps/desktop/vitruvian-courier/engine/internal/store",
        "//apps/desktop/vitruvian-courier/engine/internal/timers",
        "@com_github_modelcontextprotocol_go_sdk//mcp",
        "@com_github_rs_zerolog//:zerolog",
        "@net_maunium_go_mautrix//bridgev2",
    ],
)

go_binary(
    name = "vitruvian-vitruvian-courier-engine",
    embed = [":vitruvian-vitruvian-courier-engine_lib"],
    visibility = ["//apps/desktop/vitruvian-courier:__subpackages__"],
    # hello's engine version: the app's version, from one constant (app/version.bzl).
    x_defs = {"main.version": VITRUVIAN_COURIER_VERSION},
)

# The test copy's engine: the same program built with the courierseed tag, so VITRUVIAN_VITRUVIAN_COURIER_SEED can fill it with a
# made-up scenario (seed_on.go, //apps/desktop/vitruvian-courier/seed). Only :VitruvianCourierTestCopy bundles it; the released app's
# engine is :vitruvian-vitruvian-courier-engine, which links no seed code (the app's release_engine_has_no_seed_test checks both).
go_binary(
    name = "vitruvian-vitruvian-vitruvian-courier-engine-seeded",
    embed = [":vitruvian-vitruvian-courier-engine_lib"],
    gotags = ["courierseed"],
    visibility = ["//apps/desktop/vitruvian-courier:__subpackages__"],
    x_defs = {"main.version": VITRUVIAN_COURIER_VERSION},
)

go_test(
    name = "vitruvian-vitruvian-courier-engine_test",
    srcs = [
        "main_test.go",
        "mcpstdio_test.go",
        "seed_e2e_test.go",
    ],
    # The tests run the real binary, found in the runfiles.
    data = [":vitruvian-vitruvian-courier-engine"],
    embed = [":vitruvian-vitruvian-courier-engine_lib"],
    env = {
        "VITRUVIAN_VITRUVIAN_COURIER_ENGINE_BIN": "$(rlocationpath :vitruvian-vitruvian-courier-engine)",
        # The version the binary was stamped with, which hello must report.
        "VITRUVIAN_VITRUVIAN_COURIER_ENGINE_VERSION": VITRUVIAN_COURIER_VERSION,
    },
    deps = [
        "//apps/desktop/vitruvian-courier/engine/internal/actions",
        "//apps/desktop/vitruvian-courier/engine/internal/datadir",
        "//apps/desktop/vitruvian-courier/engine/internal/engine",
        "//apps/desktop/vitruvian-courier/engine/internal/entitlement",
        "//apps/desktop/vitruvian-courier/engine/internal/fakenet",
        "//apps/desktop/vitruvian-courier/engine/internal/localapi",
        "//apps/desktop/vitruvian-courier/engine/internal/logscrub",
        "//apps/desktop/vitruvian-courier/engine/internal/media",
        "//apps/desktop/vitruvian-courier/engine/internal/networks",
        "//apps/desktop/vitruvian-courier/engine/internal/rpc",
        "//apps/desktop/vitruvian-courier/engine/internal/seed",
        "//apps/desktop/vitruvian-courier/engine/internal/store",
        "//apps/desktop/vitruvian-courier/engine/internal/store/storetest",
        "@com_github_modelcontextprotocol_go_sdk//mcp",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
        "@net_maunium_go_mautrix//bridgev2",
    ],
)

# The seeded engine end to end (seed_e2e_test.go): it plays a scenario into an empty data folder, and only once.
# Built with the courierseed tag, against the seeded binary; only its seed tests run (main_test.go is its harness).
go_test(
    name = "vitruvian-vitruvian-courier-engine_seed_test",
    srcs = [
        "main_test.go",
        "mcpstdio_test.go",
        "seed_e2e_test.go",
    ],
    args = ["-test.run=^TestSeed"],
    data = [
        ":vitruvian-vitruvian-vitruvian-courier-engine-seeded",
        "//apps/desktop/vitruvian-courier/seed:scenarios",
    ],
    embed = [":vitruvian-vitruvian-courier-engine_lib"],
    env = {
        "VITRUVIAN_VITRUVIAN_COURIER_ENGINE_BIN": "$(rlocationpath :vitruvian-vitruvian-vitruvian-courier-engine-seeded)",
        "VITRUVIAN_VITRUVIAN_COURIER_ENGINE_VERSION": VITRUVIAN_COURIER_VERSION,
        "VITRUVIAN_VITRUVIAN_VITRUVIAN_COURIER_SEED_SCENARIOS": "$(rlocationpaths //apps/desktop/vitruvian-courier/seed:scenarios)",
    },
    gotags = ["courierseed"],
    deps = [
        "//apps/desktop/vitruvian-courier/engine/internal/actions",
        "//apps/desktop/vitruvian-courier/engine/internal/datadir",
        "//apps/desktop/vitruvian-courier/engine/internal/engine",
        "//apps/desktop/vitruvian-courier/engine/internal/entitlement",
        "//apps/desktop/vitruvian-courier/engine/internal/fakenet",
        "//apps/desktop/vitruvian-courier/engine/internal/localapi",
        "//apps/desktop/vitruvian-courier/engine/internal/logscrub",
        "//apps/desktop/vitruvian-courier/engine/internal/media",
        "//apps/desktop/vitruvian-courier/engine/internal/networks",
        "//apps/desktop/vitruvian-courier/engine/internal/rpc",
        "//apps/desktop/vitruvian-courier/engine/internal/seed",
        "//apps/desktop/vitruvian-courier/engine/internal/store",
        "//apps/desktop/vitruvian-courier/engine/internal/store/storetest",
        "@com_github_modelcontextprotocol_go_sdk//mcp",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
        "@net_maunium_go_mautrix//bridgev2",
    ],
)
