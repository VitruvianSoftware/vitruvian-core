# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files([
    "kind-cluster.sh",
    "agy",
    "copilot",
])

# --- Legacy shell wrappers ---------------------------------------------------

sh_binary(
    name = "kind-cluster-sh",
    srcs = ["kind-cluster.sh"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "agy-sh",
    srcs = ["agy"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "copilot-sh",
    srcs = ["copilot"],
    visibility = ["//visibility:public"],
)

# --- Rust port ----------------------------------------------------------------

rust_library(
    name = "scripts_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/bin/*.rs"],
    ),
    crate_name = "scripts_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "kind-cluster",
    srcs = ["src/bin/kind_cluster.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":scripts_lib"],
)

alias(
    name = "kind-cluster-rs",
    actual = ":kind-cluster",
    visibility = ["//visibility:public"],
)

rust_binary(
    name = "agy-bin",
    srcs = ["src/bin/agy.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":scripts_lib"],
)

alias(
    name = "agy-rs",
    actual = ":agy-bin",
    visibility = ["//visibility:public"],
)

rust_binary(
    name = "copilot-bin",
    srcs = ["src/bin/copilot.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":scripts_lib"],
)

alias(
    name = "copilot-rs",
    actual = ":copilot-bin",
    visibility = ["//visibility:public"],
)

# --- Tests --------------------------------------------------------------------

rust_test(
    name = "scripts_lib_test",
    size = "small",
    crate = ":scripts_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

sh_test(
    name = "scripts-parity_test",
    size = "medium",
    srcs = ["scripts-parity_test.sh"],
    args = [
        "$(rootpath kind-cluster.sh)",
        "$(rootpath :kind-cluster)",
        "$(rootpath agy)",
        "$(rootpath :agy-bin)",
        "$(rootpath copilot)",
        "$(rootpath :copilot-bin)",
    ],
    data = [
        "kind-cluster.sh",
        ":kind-cluster",
        "agy",
        ":agy-bin",
        "copilot",
        ":copilot-bin",
    ],
)

alias(
    name = "scripts_parity_test",
    actual = ":scripts-parity_test",
)
