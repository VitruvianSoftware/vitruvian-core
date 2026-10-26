# `bazel run //tools/worktree -- <branch> [base]` — create an isolated git
# worktree that gets its own Bazel server (issue #455); `-- --prune` removes the
# clean, landed, unlocked ones, and landed branches that have no worktree (dry
# run unless `--execute`). See worktree.sh.
#
# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["worktree.sh"])

rust_library(
    name = "worktree_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    compile_data = ["worktree.sh"],
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "worktree",
    srcs = ["src/main.rs"],
    # --remove --delete-branch and --prune gate on `landed.sh --branch`.
    data = ["//tools/landed:landed.sh"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":worktree_lib"],
)

sh_binary(
    name = "worktree-sh",
    srcs = ["worktree.sh"],
    # --remove --delete-branch and --prune gate on `landed.sh --branch`.
    data = ["//tools/landed:landed.sh"],
    visibility = ["//visibility:public"],
)

# Puts the main checkout back on main when a session started with its branch
# checked out there, so `worktree <branch>` can then give that branch a worktree.
sh_binary(
    name = "release-main",
    srcs = ["release-main.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "release-main_test",
    size = "small",
    srcs = ["release-main_test.sh"],
    args = ["$(location release-main.sh)"],
    data = ["release-main.sh"],
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

sh_test(
    name = "worktree_test",
    size = "small",
    srcs = ["worktree_test.sh"],
    args = [
        "$(location worktree.sh)",
        "$(location //tools/landed:landed.sh)",
    ],
    data = [
        "worktree.sh",
        "//tools/landed:landed.sh",
    ],
)

sh_test(
    name = "worktree-rs_test",
    size = "small",
    srcs = ["worktree_test.sh"],
    args = [
        "$(location :worktree)",
        "$(location //tools/landed:landed.sh)",
    ],
    data = [
        ":worktree",
        "//tools/landed:landed.sh",
    ],
)

sh_test(
    name = "worktree-rs-parity_test",
    size = "medium",
    srcs = ["worktree-rs-parity_test.sh"],
    args = [
        "$(location worktree.sh)",
        "$(location :worktree)",
        "$(location //tools/landed:landed.sh)",
    ],
    data = [
        "worktree.sh",
        ":worktree",
        "//tools/landed:landed.sh",
    ],
    shard_count = 4,
)
