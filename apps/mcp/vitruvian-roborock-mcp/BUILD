"""vitruvian-roborock-mcp: local daemon, CLI (rrctl) and MCP server for Roborock vacuums."""

# Hand-written: gazelle has no Rust extension here, and the plugin manifests
# are data, not code.
# gazelle:ignore
# gazelle:exclude plugin
# gazelle:exclude rust_src

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

package(default_visibility = ["//apps/mcp/vitruvian-roborock-mcp:__subpackages__"])

exports_files([
    "Cargo.lock",
    "Cargo.toml",
])

# The crates come from apps/mcp/vitruvian-roborock-mcp/Cargo.toml through the
# @vitruvian_roborock_mcp_crates hub (MODULE.bazel), so `cargo install` in the
# standalone mirror and Bazel here build the same dependency set.
_CRATES = [
    "@vitruvian_roborock_mcp_crates//:aes",
    "@vitruvian_roborock_mcp_crates//:aes-gcm",
    "@vitruvian_roborock_mcp_crates//:base64",
    "@vitruvian_roborock_mcp_crates//:crc32fast",
    "@vitruvian_roborock_mcp_crates//:flate2",
    "@vitruvian_roborock_mcp_crates//:getrandom",
    "@vitruvian_roborock_mcp_crates//:hmac",
    "@vitruvian_roborock_mcp_crates//:md-5",
    "@vitruvian_roborock_mcp_crates//:png",
    "@vitruvian_roborock_mcp_crates//:rustls",
    "@vitruvian_roborock_mcp_crates//:sentry",
    "@vitruvian_roborock_mcp_crates//:serde",
    "@vitruvian_roborock_mcp_crates//:serde_json",
    "@vitruvian_roborock_mcp_crates//:sha2",
    "@vitruvian_roborock_mcp_crates//:ureq",
    "@vitruvian_roborock_mcp_crates//:webpki-roots",
]

rust_library(
    name = "vitruvian_roborock_mcp_lib",
    srcs = glob(
        ["rust_src/*.rs"],
        exclude = ["rust_src/main.rs"],
    ),
    # The dashboard is compiled in with include_str!.
    compile_data = ["assets/dashboard.html"],
    crate_name = "vitruvian_roborock_mcp_rs_lib",
    crate_root = "rust_src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = _CRATES,
)

# `bazel run //apps/mcp/vitruvian-roborock-mcp:rrctl -- status`
rust_binary(
    name = "rrctl",
    srcs = ["rust_src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        ":vitruvian_roborock_mcp_lib",
        "@vitruvian_roborock_mcp_crates//:sentry",
    ],
)

rust_test(
    name = "vitruvian_roborock_mcp_test",
    size = "small",
    # Read with include_str! by the release-metadata tests in lib.rs.
    compile_data = [
        ".claude-plugin/marketplace.json",
        "Cargo.toml",
        "assets/dashboard.html",
        ":plugin",
    ],
    crate = ":vitruvian_roborock_mcp_lib",
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

# The mirror's Sponsor button. The stripe stack's donations_pages_test.go
# checks it opens a donate page that a Payment Link backs.
exports_files(
    [
        ".github/FUNDING.yml",
    ],
    visibility = ["//infrastructure/pulumi/platform/stripe:__pkg__"],
)
