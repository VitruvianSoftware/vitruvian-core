load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:ignore

package(default_visibility = ["//apps/suites/vitruvian-relay:__subpackages__"])

# The Vitruvian Relay P0 spike server (docs/superpowers/plans/2026-11-09-relay-p0-spikes.md).
# vitruvian-slack-mcp's token verifier comes from its Bazel library, not the crate hub.

_CRATES = [
    "@vitruvian_relay_spike_crates//:bytes",
    "@vitruvian_relay_spike_crates//:futures-util",
    "@vitruvian_relay_spike_crates//:http",
    "@vitruvian_relay_spike_crates//:http-body-util",
    "@vitruvian_relay_spike_crates//:hyper",
    "@vitruvian_relay_spike_crates//:hyper-util",
    "@vitruvian_relay_spike_crates//:sentry",
    "@vitruvian_relay_spike_crates//:serde_json",
    "@vitruvian_relay_spike_crates//:tokio",
    "@vitruvian_relay_spike_crates//:tokio-tungstenite",
]

rust_library(
    name = "vitruvian_relay_spike_lib",
    srcs = [
        "src/client.rs",
        "src/lib.rs",
    ],
    crate_name = "vitruvian_relay_spike",
    crate_root = "src/lib.rs",
    edition = "2021",
    deps = ["@vitruvian_relay_spike_crates//:serde_json"],
)

rust_binary(
    name = "vitruvian-relay-spike",
    srcs = ["src/main.rs"],
    crate_root = "src/main.rs",
    edition = "2021",
    deps = _CRATES + [
        ":vitruvian_relay_spike_lib",
        "//apps/mcp/vitruvian-slack-mcp:vitruvian_slack_mcp_lib",
    ],
)

# The spike's test client: device-flow sign-in (spike B) and a day-long hold
# on /connect (spike C). See README.md. rustls and ureq come from
# vitruvian-slack-mcp's hub, not ours: the client passes its TLS config to
# them, and Bazel treats the same crate from two hubs as two different crates.
rust_binary(
    name = "vitruvian-relay-spike-client",
    srcs = ["src/client_main.rs"],
    crate_root = "src/client_main.rs",
    edition = "2021",
    deps = [
        ":vitruvian_relay_spike_lib",
        "//apps/mcp/vitruvian-slack-mcp:vitruvian_slack_mcp_lib",
        "@vitruvian_relay_spike_crates//:serde_json",
        "@vitruvian_relay_spike_crates//:tokio-tungstenite",
        "@vitruvian_slack_mcp_crates//:rustls",
        "@vitruvian_slack_mcp_crates//:ureq",
    ],
)

rust_test(
    name = "vitruvian_relay_spike_test",
    size = "small",
    crate = ":vitruvian_relay_spike_lib",
)

test_suite(
    name = "unit_tests",
    tests = [":vitruvian_relay_spike_test"],
)

pipeline_unit(
    name = "vitruvian-relay-spike-service",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [":unit_tests"],
    tier = "L1",
    timeout_minutes = 15,
)
