# gazelle:ignore
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["bazel-cache.sh"])

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

sh_binary(
    name = "gc-sh",
    srcs = ["bazel-cache.sh"],
    args = ["gc"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "bazel-cache_test",
    size = "small",
    srcs = ["bazel-cache_test.sh"],
    data = ["bazel-cache.sh"],
)

sh_test(
    name = "gc-rs_test",
    size = "small",
    srcs = ["bazel-cache_test.sh"],
    args = ["$(rootpath :gc)"],
    data = [":gc"],
)

rust_test(
    name = "bazel_cache_lib_test",
    size = "small",
    crate = ":bazel_cache_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

sh_test(
    name = "gc-rs-parity_test",
    size = "medium",
    srcs = ["bazel-cache-rs-parity_test.sh"],
    args = [
        "$(rootpath :bazel-cache.sh)",
        "$(rootpath :gc)",
    ],
    data = [
        "bazel-cache.sh",
        ":gc",
    ],
)
