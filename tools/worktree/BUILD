# `bazel run //tools/worktree -- <branch> [base]` — create an isolated git
# worktree that gets its own Bazel server (issue #455). See worktree.sh.

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

sh_binary(
    name = "worktree",
    srcs = ["worktree.sh"],
    visibility = ["//visibility:public"],
)

exports_files(["worktree.sh"])
