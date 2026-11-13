load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//tools/doctor:defs.bzl", "doctor")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:ignore
# gazelle:exclude rs

# Inter-app boundary (#82): default targets to vitruvian-slack-mcp-internal visibility so
# other top-level apps can't depend on internals. The published artifact is
# built by label (`bazel build //apps/mcp/vitruvian-slack-mcp:vitruvian-slack-mcp`) which ignores visibility, so even
# the published target needs no wider scope.
package(default_visibility = ["//apps/mcp/vitruvian-slack-mcp:__subpackages__"])

test_suite(
    name = "unit_tests",
    tests = [":vitruvian_slack_mcp_test"],
)

_CRATES = [
    "@vitruvian_slack_mcp_crates//:bytes",
    "@vitruvian_slack_mcp_crates//:http",
    "@vitruvian_slack_mcp_crates//:http-body-util",
    "@vitruvian_slack_mcp_crates//:hyper",
    "@vitruvian_slack_mcp_crates//:hyper-util",
    "@vitruvian_slack_mcp_crates//:ring",
    "@vitruvian_slack_mcp_crates//:rustls",
    "@vitruvian_slack_mcp_crates//:rustls-native-certs",
    "@vitruvian_slack_mcp_crates//:serde_json",
    "@vitruvian_slack_mcp_crates//:tokio",
    "@vitruvian_slack_mcp_crates//:ureq",
]

# The Vitruvian Slack MCP server (rs/Cargo.toml, locked in rs/Cargo.lock).
rust_library(
    name = "vitruvian_slack_mcp_lib",
    srcs = [
        "rs/src/auth.rs",
        "rs/src/channel_allowlist.rs",
        "rs/src/config.rs",
        "rs/src/dispatch.rs",
        "rs/src/http_transport.rs",
        "rs/src/lib.rs",
        "rs/src/permalink.rs",
        "rs/src/slack_client.rs",
        "rs/src/tools.rs",
    ],
    crate_name = "vitruvian_slack_mcp_rs_lib",
    crate_root = "rs/src/lib.rs",
    edition = "2021",
    # One narrow exception to the inter-app boundary (#82): the Vitruvian Relay P0 spike
    # reuses this crate's token verifier instead of copying it. The relay spec
    # (docs/superpowers/specs/2026-11-07-vitruvian-relay-design.md §5) moves
    # the verifier into a shared crate before P1; this line goes with it.
    visibility = [
        "//apps/mcp/vitruvian-slack-mcp:__subpackages__",
        "//apps/suites/vitruvian-relay/spike:__pkg__",
    ],
    deps = _CRATES,
)

rust_binary(
    name = "vitruvian-slack-mcp",
    srcs = ["rs/src/main.rs"],
    crate_root = "rs/src/main.rs",
    edition = "2021",
    deps = [":vitruvian_slack_mcp_lib"],
)

rust_test(
    name = "vitruvian_slack_mcp_test",
    size = "small",
    crate = ":vitruvian_slack_mcp_lib",
    data = [
        "README.md",
        "rs/src/testdata_main_tools_list.json",
    ],
)

# Developer-environment check: `bazel run //apps/mcp/vitruvian-slack-mcp:doctor`.
doctor(
    name = "doctor",
    label = "vitruvian-slack-mcp",
    required = [
        "bazel",
        "git",
    ],
)

pipeline_unit(
    name = "vitruvian-slack-mcp-service",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":unit_tests",
        ":vitruvian_slack_mcp_test",
    ],
    tier = "L1",
    timeout_minutes = 15,
)

# The mirror's Sponsor button. The stripe stack's donations_pages_test.go
# checks it opens a donate page that a Payment Link backs.
exports_files(
    [
        ".github/FUNDING.yml",
    ],
    visibility = ["//infrastructure/pulumi/platform/stripe:__pkg__"],
)
