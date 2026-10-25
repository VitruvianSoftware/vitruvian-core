"""The git writes agents make, with the safety checks built in.

  bazel run //tools/git:commit -- -m "fix(scope): what changed" <paths>...
  bazel run //tools/git:push [-- --agent <name>] [-- --force-with-lease]
  bazel run //tools/git:sync [-- --autosquash | --merge | --abort]

Agents are about to be blocked from raw `git commit`, `git push`, `git rebase`
and friends (a hook reads their commands; `bazel run` is what it lets through).
These are the replacements: commit refuses on main and in the main checkout and
secret-scans what it records; push never writes main, never plain-forces, and
scans what it publishes; sync never stashes, since the stash is shared by every
worktree. See README.md.
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

_DATA = [
    "//:.gitleaks.toml",
    "//tools/agent-app:agent-app.sh",
    "//tools/secret-scan:secret-scan.sh",
    "@multitool//tools/gitleaks",
]

rust_library(
    name = "git_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    compile_data = ["git.sh"],
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "git",
    srcs = ["src/main.rs"],
    data = _DATA,
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":git_lib"],
)

rust_binary(
    name = "commit",
    srcs = ["src/main.rs"],
    args = ["commit"],
    data = _DATA,
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":git_lib"],
)

rust_binary(
    name = "push",
    srcs = ["src/main.rs"],
    args = ["push"],
    data = _DATA,
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":git_lib"],
)

rust_binary(
    name = "sync",
    srcs = ["src/main.rs"],
    args = ["sync"],
    data = _DATA,
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":git_lib"],
)

alias(
    name = "git-rs",
    actual = ":git",
    visibility = ["//visibility:public"],
)

alias(
    name = "git_rs",
    actual = ":git",
    visibility = ["//visibility:public"],
)

alias(
    name = "commit-rs",
    actual = ":commit",
    visibility = ["//visibility:public"],
)

alias(
    name = "commit_rs",
    actual = ":commit",
    visibility = ["//visibility:public"],
)

alias(
    name = "push-rs",
    actual = ":push",
    visibility = ["//visibility:public"],
)

alias(
    name = "push_rs",
    actual = ":push",
    visibility = ["//visibility:public"],
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

sh_binary(
    name = "commit-sh",
    srcs = ["git.sh"],
    args = ["commit"],
    data = _DATA,
    visibility = ["//visibility:public"],
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

sh_binary(
    name = "push-sh",
    srcs = ["git.sh"],
    args = ["push"],
    data = _DATA,
    visibility = ["//visibility:public"],
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

sh_binary(
    name = "sync-sh",
    srcs = ["git.sh"],
    args = ["sync"],
    data = _DATA,
    visibility = ["//visibility:public"],
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

# Throwaway repos, a bare repo as origin, the real pinned gitleaks, and a fake
# agent-app: no network, never the real repo.
sh_test(
    name = "git_test",
    size = "medium",
    srcs = ["git_test.sh"],
    args = ["$(location git.sh)"],
    data = ["git.sh"] + _DATA,
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

sh_test(
    name = "git-rs_test",
    size = "medium",
    srcs = ["git_test.sh"],
    args = ["$(location :git)"],
    data = [":git"] + _DATA,
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

rust_test(
    name = "git_lib_test",
    size = "small",
    crate = ":git_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

sh_test(
    name = "git-rs-parity_test",
    size = "medium",
    srcs = ["git-rs-parity_test.sh"],
    args = [
        "$(location git.sh)",
        "$(location :git)",
    ],
    data = [
        "git.sh",
        ":git",
    ] + _DATA,
    shard_count = 3,
    deps = ["@bazel_tools//tools/bash/runfiles"],
)
