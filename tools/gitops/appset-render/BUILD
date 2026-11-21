# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# What CI jobs without Bazel compile with plain rustc
# (//tools/ci:build_ci_tool_test and
# //packages/rust/vitruvian-pycompat:rustc_build_test run those lines).
filegroup(
    name = "srcs",
    srcs = glob(["src/**/*.rs"]),
    visibility = [
        "//packages/rust/vitruvian-pycompat:__pkg__",
        "//tools/ci:__pkg__",
    ],
)

rust_library(
    name = "appset_render_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "appset_render",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = ["//packages/rust/vitruvian-pycompat:vitruvian_pycompat"],
)

# `bazel run //tools/gitops/appset-render` — check every ApplicationSet under
# gitops/argocd parses as the ArgoCD controller would parse it.
rust_binary(
    name = "appset-render",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":appset_render_lib"],
)

alias(
    name = "appset_render",
    actual = ":appset-render",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "appset-render_test",
    size = "small",
    crate = ":appset_render_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "appset_render_test",
    tests = [":appset-render_test"],
)

test_suite(
    name = "appset_render_lib_test",
    tests = [":appset-render_test"],
)
