load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:ignore

# The shared Zitadel token checker. The Slack MCP is added to this list when it
# moves over; until then it builds from its own hub, and one crate from two hubs
# is two crates.
package(default_visibility = ["//apps/suites/vitruvian-relay:__subpackages__"])

_CRATES = [
    "@vitruvian_relay_crates//:ring",
    "@vitruvian_relay_crates//:rustls",
    "@vitruvian_relay_crates//:rustls-native-certs",
    "@vitruvian_relay_crates//:serde_json",
    "@vitruvian_relay_crates//:ureq",
]

rust_library(
    name = "vitruvian_mcp_auth",
    srcs = [
        "src/lib.rs",
        "src/prm.rs",
        "src/verifier.rs",
    ],
    crate_name = "vitruvian_mcp_auth",
    crate_root = "src/lib.rs",
    edition = "2021",
    deps = _CRATES,
)

rust_test(
    name = "vitruvian_mcp_auth_test",
    size = "small",
    crate = ":vitruvian_mcp_auth",
)

test_suite(
    name = "unit_tests",
    tests = [":vitruvian_mcp_auth_test"],
)

pipeline_unit(
    name = "vitruvian-mcp-auth",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [":unit_tests"],
    tier = "L1",
    timeout_minutes = 15,
)
