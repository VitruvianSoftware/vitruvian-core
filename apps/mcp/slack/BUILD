load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//tools/doctor:defs.bzl", "doctor")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:ignore
# gazelle:exclude rs

# Inter-app boundary (#82): default targets to mcp-slack-internal visibility so
# other top-level apps can't depend on internals. The npm-published artifact is
# built by label (`bazel build //mcp-slack`) which ignores visibility, so even
# the published target needs no wider scope.
package(default_visibility = ["//apps/mcp/slack:__subpackages__"])

alias(
    name = "mcp-slack",
    actual = ":mcp-slack-rs",
)

test_suite(
    name = "unit_tests",
    tests = [":mcp_slack_rs_test"],
)

_CRATES = [
    "@mcp_slack_crates//:bytes",
    "@mcp_slack_crates//:http",
    "@mcp_slack_crates//:http-body-util",
    "@mcp_slack_crates//:hyper",
    "@mcp_slack_crates//:hyper-util",
    "@mcp_slack_crates//:ring",
    "@mcp_slack_crates//:rustls",
    "@mcp_slack_crates//:rustls-native-certs",
    "@mcp_slack_crates//:serde_json",
    "@mcp_slack_crates//:tokio",
    "@mcp_slack_crates//:ureq",
]

# The Slack MCP server (rs/Cargo.toml, locked in rs/Cargo.lock).
rust_library(
    name = "mcp_slack_rs_lib",
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
    crate_root = "rs/src/lib.rs",
    edition = "2021",
    deps = _CRATES,
)

rust_binary(
    name = "mcp-slack-rs",
    srcs = ["rs/src/main.rs"],
    crate_root = "rs/src/main.rs",
    edition = "2021",
    deps = [":mcp_slack_rs_lib"],
)

alias(
    name = "mcp_slack_rs",
    actual = ":mcp-slack-rs",
)

rust_test(
    name = "mcp_slack_rs_test",
    size = "small",
    crate = ":mcp_slack_rs_lib",
    data = [
        "README.md",
    ],
)

# Developer-environment check: `bazel run //mcp-slack:doctor`.
doctor(
    name = "doctor",
    label = "mcp-slack",
    required = [
        "bazel",
        "git",
    ],
)

pipeline_unit(
    name = "mcp-slack-service",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":unit_tests",
        ":mcp_slack_rs_test",
    ],
    tier = "L1",
    timeout_minutes = 15,
)
