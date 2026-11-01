"""vitruvian-roborock: local daemon, CLI (rrctl) and MCP server for Roborock vacuums."""

# Hand-written: gazelle has no Rust extension here, and the plugin manifests
# are data, not code.
# gazelle:ignore
# gazelle:exclude plugin
# gazelle:exclude rust_src

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

package(default_visibility = ["//apps/mcp/roborock:__subpackages__"])

exports_files([
    "Cargo.lock",
    "Cargo.toml",
])

# The crates come from apps/mcp/roborock/Cargo.toml through the
# @mcp_roborock_crates hub (MODULE.bazel), so `cargo install` in the
# standalone mirror and Bazel here build the same dependency set.
_CRATES = [
    "@mcp_roborock_crates//:aes",
    "@mcp_roborock_crates//:aes-gcm",
    "@mcp_roborock_crates//:base64",
    "@mcp_roborock_crates//:crc32fast",
    "@mcp_roborock_crates//:flate2",
    "@mcp_roborock_crates//:getrandom",
    "@mcp_roborock_crates//:hmac",
    "@mcp_roborock_crates//:md-5",
    "@mcp_roborock_crates//:png",
    "@mcp_roborock_crates//:rustls",
    "@mcp_roborock_crates//:serde",
    "@mcp_roborock_crates//:serde_json",
    "@mcp_roborock_crates//:sha2",
    "@mcp_roborock_crates//:ureq",
    "@mcp_roborock_crates//:webpki-roots",
]

rust_library(
    name = "roborock_lib",
    srcs = glob(
        ["rust_src/*.rs"],
        exclude = ["rust_src/main.rs"],
    ),
    # The dashboard is compiled in with include_str!.
    compile_data = ["assets/dashboard.html"],
    crate_name = "roborock_rs_lib",
    crate_root = "rust_src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = _CRATES,
)

# `bazel run //apps/mcp/roborock:rrctl -- status`
rust_binary(
    name = "rrctl",
    srcs = ["rust_src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":roborock_lib"],
)

rust_test(
    name = "roborock_test",
    size = "small",
    # Read with include_str! by the release-metadata tests in lib.rs.
    compile_data = [
        ".claude-plugin/marketplace.json",
        "Cargo.toml",
        "assets/dashboard.html",
        ":plugin",
    ],
    crate = ":roborock_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# The plugin manifests, for anything that packages or validates them.
filegroup(
    name = "plugin",
    srcs = glob(
        ["plugin/**"],
        exclude_directories = 1,
    ),
)
