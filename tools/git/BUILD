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

_DATA = [
    "//:.gitleaks.toml",
    "//tools/agent-app:agent-app",
    "//tools/agent-app:agent-app.sh",
    "//tools/secret-scan:secret-scan",
    "//tools/secret-scan:secret-scan.sh",
    "@multitool//tools/gitleaks",
]

rust_library(
    name = "git_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
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

rust_test(
    name = "git_lib_test",
    size = "small",
    crate = ":git_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "git_test",
    tests = [":git_lib_test"],
)

# agent-guard reads this file to check its refusal advice names a real target
# (//tools/agent-guard:pending_target_files).
exports_files(
    ["BUILD"],
    visibility = ["//tools/agent-guard:__pkg__"],
)
