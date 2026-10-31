# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "conflict_precheck_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "conflict_precheck",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# `bazel run //tools/copybara/conflict-precheck` — what the export workflow runs.
rust_binary(
    name = "conflict-precheck",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":conflict_precheck_lib"],
)

alias(
    name = "conflict_precheck",
    actual = ":conflict-precheck",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "conflict-precheck_test",
    size = "small",
    crate = ":conflict_precheck_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "conflict_precheck_test",
    tests = [":conflict-precheck_test"],
)

test_suite(
    name = "conflict_precheck_lib_test",
    tests = [":conflict-precheck_test"],
)
