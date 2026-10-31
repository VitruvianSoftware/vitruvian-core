# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

# Hand-written: the Rust targets below are not gazelle's to own.
# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# The export version maps in copy.bara.sky rewrite in-tree references to
# PUBLISHED versions for the standalone mirrors. They were hand-maintained,
# guarded only by a "keep in sync" comment, and had drifted in 35 of 42 entries
# -- leaving ts-example-foundation unable to resolve its own dependencies.
rust_library(
    name = "check_version_maps_lib",
    srcs = ["src/lib.rs"],
    crate_name = "check_version_maps",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "check-version-maps",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":check_version_maps_lib"],
)

alias(
    name = "check_version_maps",
    actual = ":check-version-maps",
    visibility = ["//visibility:public"],
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "check_version_maps_lib_test",
    size = "small",
    crate = ":check_version_maps_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "check_version_maps_test",
    tests = [":check_version_maps_lib_test"],
)

# //tools/registry-trust reads COMPONENTS to learn which mirror publishes a
# package; its test reads the real file so a layout change cannot hide one.
exports_files(
    ["copy.bara.sky"],
    visibility = ["//tools/registry-trust:__pkg__"],
)
