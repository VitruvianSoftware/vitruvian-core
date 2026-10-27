# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "copybara_sync_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "copybara_sync",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

alias(
    name = "sync_rs_lib",
    actual = ":copybara_sync_lib",
)

# `bazel run //tools/copybara/sync -- <export|import> <component>` and
# `... -- import_pr <component> <pr-number>`: what the Copybara workflows run.
rust_binary(
    name = "sync",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":copybara_sync_lib"],
)

alias(
    name = "sync-rs",
    actual = ":sync",
    visibility = ["//visibility:public"],
)

alias(
    name = "sync_rs",
    actual = ":sync",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "sync_test",
    size = "small",
    crate = ":copybara_sync_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "copybara_sync_lib_test",
    tests = [":sync_test"],
)

test_suite(
    name = "sync_rs_lib_test",
    tests = [":sync_test"],
)
