# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

# Asks the REGISTRY whether our published packages are actually there, rather
# than asking the pipeline whether it thinks it published them. Those stopped
# being the same thing on 2026-05-07 and nothing noticed for three months.
sh_binary(
    name = "check",
    srcs = ["check.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "check_test",
    size = "small",
    srcs = ["check_test.sh"],
    args = ["$(location check.sh)"],
    data = ["check.sh"],
)
