load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:ignore

package(default_visibility = ["//apps/suites/relay:__subpackages__"])

# The relay P0 spike server (docs/superpowers/plans/2026-11-09-relay-p0-spikes.md).
# mcp-slack's token verifier comes from its Bazel library, not the crate hub.

_CRATES = [
    "@relay_spike_crates//:bytes",
    "@relay_spike_crates//:futures-util",
    "@relay_spike_crates//:http",
    "@relay_spike_crates//:http-body-util",
    "@relay_spike_crates//:hyper",
    "@relay_spike_crates//:hyper-util",
    "@relay_spike_crates//:serde_json",
    "@relay_spike_crates//:tokio",
    "@relay_spike_crates//:tokio-tungstenite",
]

rust_library(
    name = "relay_spike_lib",
    srcs = ["src/lib.rs"],
    crate_name = "relay_spike",
    crate_root = "src/lib.rs",
    edition = "2021",
    deps = ["@relay_spike_crates//:serde_json"],
)

rust_binary(
    name = "relay-spike",
    srcs = ["src/main.rs"],
    crate_root = "src/main.rs",
    edition = "2021",
    deps = _CRATES + [
        ":relay_spike_lib",
        "//apps/mcp/slack:mcp_slack_lib",
    ],
)

rust_test(
    name = "relay_spike_test",
    size = "small",
    crate = ":relay_spike_lib",
)

test_suite(
    name = "unit_tests",
    tests = [":relay_spike_test"],
)

pipeline_unit(
    name = "relay-spike-service",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [":unit_tests"],
    tier = "L1",
    timeout_minutes = 15,
)
