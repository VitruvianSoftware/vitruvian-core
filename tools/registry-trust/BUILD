# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Registry trust in code: which registry trusts which workflow, and proof
that a released version came from that workflow and not from a person."""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "registry_trust_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    compile_data = [
        "bootstrap.tsv",
        "//tools/copybara:copy.bara.sky",
    ] + glob(["testdata/*.json"]),
    crate_name = "registry_trust",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
)

rust_binary(
    name = "inventory",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":registry_trust_lib"],
)

rust_binary(
    name = "check",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":registry_trust_lib"],
)

rust_binary(
    name = "setup",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":registry_trust_lib"],
)

rust_test(
    name = "registry_trust_lib_test",
    size = "small",
    compile_data = [
        "bootstrap.tsv",
        "//tools/copybara:copy.bara.sky",
    ] + glob(["testdata/*.json"]),
    crate = ":registry_trust_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "inventory_test",
    tests = [":registry_trust_lib_test"],
)

test_suite(
    name = "check_test",
    tests = [":registry_trust_lib_test"],
)

test_suite(
    name = "setup_test",
    tests = [":registry_trust_lib_test"],
)
