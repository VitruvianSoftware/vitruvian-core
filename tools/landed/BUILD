"""Did this work actually land on main?

  bazel run //tools/landed -- 1205                 # a PR number
  bazel run //tools/landed -- claude/my-branch     # a branch
  bazel run //tools/landed -- da6612ad             # a local commit

`main` is squash-only (enforced by the repo_config ruleset), so a topic branch's
commits are REWRITTEN on merge and their SHAs are never ancestors of main. The
obvious `git merge-base --is-ancestor <branch-sha> origin/main` therefore reports
every merged PR as missing -- a false negative on work that is actually landed.
This resolves the durable identity (the PR number) to the squashed commit and
verifies THAT against origin/main. See tools/landed/landed.sh for the full why.
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

sh_binary(
    name = "landed",
    srcs = ["landed.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "landed_test",
    size = "small",
    srcs = ["landed_test.sh"],
    data = ["landed.sh"],
)
