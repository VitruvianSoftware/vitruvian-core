# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["parity.sh"])

sh_binary(
    name = "parity-sh",
    srcs = ["parity.sh"],
    visibility = ["//visibility:public"],
)

rust_library(
    name = "parity_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "parity_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "parity",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":parity_lib"],
)

alias(
    name = "parity-rs",
    actual = ":parity",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "parity_lib_test",
    size = "small",
    crate = ":parity_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

sh_test(
    name = "parity_test",
    size = "medium",
    srcs = ["parity_test.sh"],
    args = [
        "$(rootpath parity.sh)",
        "$(rootpath :parity)",
    ],
    data = [
        "parity.sh",
        ":parity",
    ],
)
