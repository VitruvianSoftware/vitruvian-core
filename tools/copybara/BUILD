# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

# Hand-written: the Rust targets below are not gazelle's to own.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_binary")
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

# //apps/web/mini-party:mirror_catalog_test reads _MINI_PARTY_CATALOG_VERSIONS.
# //tools/registry-trust reads COMPONENTS to learn which mirror publishes a
# package; its test reads the real file so a layout change cannot hide one.
exports_files(
    ["copy.bara.sky"],
    visibility = [
        "//apps/web/mini-party:__pkg__",
        "//tools/registry-trust:__pkg__",
    ],
)

# Assembles the exported vitruvian-sdk mirror tree from copy.bara.sky and runs
# the mirror's Cargo checks against it (including the vendored pycompat path).
py_binary(
    name = "sdk_export_check",
    srcs = ["sdk_export_check.py"],
    data = [
        "@rules_rust//rust/toolchain:current_cargo_files",
        "@rules_rust//rust/toolchain:current_rust_stdlib_files",
        "@rules_rust//rust/toolchain:current_rust_toolchain",
        "@rules_rust//rust/toolchain:current_rustc_files",
        "@rules_rust//rust/toolchain:current_rustc_lib_files",
        "@rules_rust//rust/toolchain:current_rustdoc_files",
    ],
    env = {
        "REAL_CARGO": "$(rootpaths @rules_rust//rust/toolchain:current_cargo_files)",
        "REAL_RUSTC": "$(rootpaths @rules_rust//rust/toolchain:current_rustc_files)",
        "REAL_RUSTDOC": "$(rootpaths @rules_rust//rust/toolchain:current_rustdoc_files)",
    },
    main = "sdk_export_check.py",
    visibility = ["//visibility:public"],
)
