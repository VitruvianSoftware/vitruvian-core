# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

"""Autonomous, robust PR check monitoring, merge queue, and post-merge pipeline verification.

  bazel run //tools/watch-pr -- <pr-number|branch|sha> [options]

Exit codes:
  0: Success (all checks passed, landed on main, post-merge pipeline green).
  1: Check or workflow failure (diagnostic logs printed).
  2: Timeout reached.
  3: Invalid argument or configuration error.
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

sh_binary(
    name = "watch-pr",
    srcs = ["watch-pr.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "watch-pr_test",
    size = "small",
    srcs = ["watch-pr_test.sh"],
    data = ["watch-pr.sh"],
)
