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

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

_DATA = [
    "//:.gitleaks.toml",
    "//tools/agent-app:agent-app.sh",
    "//tools/secret-scan:secret-scan.sh",
    "@multitool//tools/gitleaks",
]

sh_binary(
    name = "commit",
    srcs = ["git.sh"],
    args = ["commit"],
    data = _DATA,
    visibility = ["//visibility:public"],
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

sh_binary(
    name = "push",
    srcs = ["git.sh"],
    args = ["push"],
    data = _DATA,
    visibility = ["//visibility:public"],
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

sh_binary(
    name = "sync",
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
