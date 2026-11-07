load("@rules_go//go:def.bzl", "go_library", "go_test")

# The app's release_engine_has_no_seed_test reads Marker from here, so the string it looks for in each bundled
# engine is the one this package compiles in.
exports_files(
    ["seed.go"],
    visibility = ["//apps/desktop/courier/app:__pkg__"],
)

go_library(
    name = "seed",
    srcs = ["seed.go"],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/seed",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
    deps = [
        "//apps/desktop/courier/engine/internal/fakenet",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//event",
    ],
)

go_test(
    name = "seed_test",
    srcs = ["seed_test.go"],
    # The scenario files the test copy plays: every one must parse and check.
    data = ["//apps/desktop/courier/seed:scenarios"],
    embed = [":seed"],
    deps = [
        "//apps/desktop/courier/engine/internal/engine",
        "//apps/desktop/courier/engine/internal/fakenet",
        "//apps/desktop/courier/engine/internal/ids",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
        "@net_maunium_go_mautrix//bridgev2",
    ],
)
