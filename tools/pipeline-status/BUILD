# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

"""Determines the complete health status of all workflows triggered on main.

  bazel run //tools/pipeline-status -- [commit-sha|pr-number]

Exit codes:
  0: All post-merge workflows on main passed (GREEN).
  1: One or more workflows failed (RED).
  2: Workflows are currently in-flight (PENDING / IN_PROGRESS).
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

sh_binary(
    name = "pipeline-status",
    srcs = ["pipeline-status.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "pipeline-status_test",
    size = "small",
    srcs = ["pipeline-status_test.sh"],
    args = ["$(location pipeline-status.sh)"],
    data = ["pipeline-status.sh"],
)
