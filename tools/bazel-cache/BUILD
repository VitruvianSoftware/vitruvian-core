# gazelle:ignore
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "bazel_cache_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "gc",
    srcs = ["src/main.rs"],
    args = ["gc"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":bazel_cache_lib"],
)

alias(
    name = "gc-rs",
    actual = ":gc",
    visibility = ["//visibility:public"],
)

alias(
    name = "gc_rs",
    actual = ":gc",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "bazel_cache_lib_test",
    size = "small",
    crate = ":bazel_cache_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "gc_test",
    tests = [":bazel_cache_lib_test"],
)

test_suite(
    name = "bazel-cache_test",
    tests = [":bazel_cache_lib_test"],
)
