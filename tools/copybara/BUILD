# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

# Hand-written: the Rust and Python targets below are not gazelle's to own.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

# The export version maps in copy.bara.sky rewrite in-tree references to
# PUBLISHED versions for the standalone mirrors. They were hand-maintained,
# guarded only by a "keep in sync" comment, and had drifted in 35 of 42 entries
# -- leaving ts-example-foundation unable to resolve its own dependencies.
#
# `:check-version-maps` is the Rust port (src/): check-version-maps.sh's
# arguments, report, exit codes and --fix rewrite, held to the script by the
# parity test below. The script stays as `:check-version-maps-sh` (and
# //tools/conformance runs it directly).
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

alias(
    name = "check-version-maps-rs",
    actual = ":check-version-maps",
    visibility = ["//visibility:public"],
)

alias(
    name = "check_version_maps_rs",
    actual = ":check-version-maps",
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "check-version-maps-sh",
    srcs = ["check-version-maps.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "check_version_maps_test",
    size = "small",
    srcs = ["check_version_maps_test.sh"],
    args = ["$(location check-version-maps.sh)"],
    data = ["check-version-maps.sh"],
)

# The same suite against the Rust binary (CHECK_VERSION_MAPS_BIN).
sh_test(
    name = "check-version-maps-rs_test",
    size = "small",
    srcs = ["check_version_maps_test.sh"],
    args = ["$(location check-version-maps.sh)"],
    data = [
        "check-version-maps.sh",
        ":check-version-maps",
    ],
    env = {"CHECK_VERSION_MAPS_BIN": "$(rootpath :check-version-maps)"},
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "check_version_maps_lib_test",
    size = "small",
    crate = ":check_version_maps_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Script and binary side by side on every case in
# check_version_maps_rs_parity_test.py: exit code, stdout, stderr and the
# rewritten copy.bara.sky, compared byte for byte.
py_test(
    name = "check_version_maps_rs_parity_test",
    size = "medium",
    srcs = ["check_version_maps_rs_parity_test.py"],
    data = [
        "check-version-maps.sh",
        ":check-version-maps",
    ],
    env = {
        "CHECK_VERSION_MAPS_RS": "$(rootpath :check-version-maps)",
        "CHECK_VERSION_MAPS_SH": "$(rootpath check-version-maps.sh)",
    },
    main = "check_version_maps_rs_parity_test.py",
    deps = ["//tools/shell-compat:parity_harness"],
)

# //tools/registry-trust reads COMPONENTS to learn which mirror publishes a
# package; its test reads the real file so a layout change cannot hide one.
exports_files(
    ["copy.bara.sky"],
    visibility = ["//tools/registry-trust:__pkg__"],
)
