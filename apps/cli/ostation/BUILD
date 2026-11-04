# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""ostation: local LAN client for the Olight Ostation 2 Pro charger."""

# Hand-written: gazelle has no Rust extension here.
# gazelle:ignore
# gazelle:exclude rust_src

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

package(default_visibility = ["//apps/cli/ostation:__subpackages__"])

exports_files([
    "Cargo.lock",
    "Cargo.toml",
])

# The crates come from apps/cli/ostation/Cargo.toml through the
# @ostation_crates hub (MODULE.bazel).
_CRATES = [
    "@ostation_crates//:aes-gcm",
    "@ostation_crates//:getrandom",
    "@ostation_crates//:hmac",
    "@ostation_crates//:serde_json",
    "@ostation_crates//:sha2",
]

rust_library(
    name = "ostation_lib",
    srcs = glob(
        ["rust_src/*.rs"],
        exclude = ["rust_src/main.rs"],
    ),
    crate_name = "ostation_lib",
    crate_root = "rust_src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = _CRATES,
)

rust_binary(
    name = "ostation",
    srcs = ["rust_src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":ostation_lib",
        "@ostation_crates//:serde_json",
    ],
)

rust_test(
    name = "ostation_test",
    size = "small",
    # The regression fixture: a real Olight app session, replayed in tests.rs.
    compile_data = ["ost_app.pcap"],
    crate = ":ostation_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)
