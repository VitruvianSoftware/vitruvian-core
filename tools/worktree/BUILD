# `bazel run //tools/worktree -- <branch> [base]` — create an isolated git
# worktree that gets its own Bazel server (issue #455); `-- --prune` removes the
# clean, landed, unlocked ones (dry run unless `--execute`). See worktree.sh.

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

sh_binary(
    name = "worktree",
    srcs = ["worktree.sh"],
    # --remove --delete-branch and --prune gate on `landed.sh --branch`.
    data = ["//tools/landed:landed.sh"],
    visibility = ["//visibility:public"],
)

exports_files(["worktree.sh"])

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
