# `bazel run //tools/worktree -- <branch> [base]` — create an isolated git
# worktree that gets its own Bazel server (issue #455); `-- --prune` removes the
# clean, landed, unlocked ones, and landed branches that have no worktree (dry
# run unless `--execute`).
#
# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "worktree_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "worktree",
    srcs = ["src/main.rs"],
    # --remove --delete-branch and --prune gate on `landed --branch`.
    data = [
        "//tools/landed",
        "//tools/landed:landed.sh",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":worktree_lib"],
)

alias(
    name = "worktree-rs",
    actual = ":worktree",
    visibility = ["//visibility:public"],
)

alias(
    name = "worktree_rs",
    actual = ":worktree",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "worktree_lib_test",
    size = "small",
    crate = ":worktree_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "worktree_test",
    tests = [":worktree_lib_test"],
)

test_suite(
    name = "worktree-rs_test",
    tests = [":worktree_lib_test"],
)
