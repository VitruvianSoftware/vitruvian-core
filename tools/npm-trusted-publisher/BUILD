# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "npm_trusted_publisher_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/bin/*.rs"],
    ),
    crate_name = "npm_trusted_publisher",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

# Configures npm trusted publishing for every publishable package in one pass.
# The npm UI re-challenges 2FA on page NAVIGATION, so doing this by hand costs
# ~62 hardware key touches; `npm trust` needs one.
rust_binary(
    name = "setup",
    srcs = ["src/bin/setup.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":npm_trusted_publisher_lib"],
)

# Gives a never-published package its FIRST publish, then hands off to setup.
# Trusted publishing attaches to a package that EXISTS, and the release workflow
# authenticates by OIDC alone -- so a brand-new name cannot be created by CI at
# all. Exactly one manual publish per package breaks that cycle.
rust_binary(
    name = "bootstrap",
    srcs = ["src/bin/bootstrap.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":npm_trusted_publisher_lib"],
)

alias(
    name = "setup-rs",
    actual = ":setup",
    visibility = ["//visibility:public"],
)

alias(
    name = "bootstrap-rs",
    actual = ":bootstrap",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "npm_trusted_publisher_lib_test",
    size = "small",
    crate = ":npm_trusted_publisher_lib",
    edition = "2021",
)

test_suite(
    name = "setup_test",
    tests = [":npm_trusted_publisher_lib_test"],
)

test_suite(
    name = "bootstrap_test",
    tests = [":npm_trusted_publisher_lib_test"],
)

test_suite(
    name = "setup-rs_test",
    tests = [":npm_trusted_publisher_lib_test"],
)

test_suite(
    name = "bootstrap-rs_test",
    tests = [":npm_trusted_publisher_lib_test"],
)
