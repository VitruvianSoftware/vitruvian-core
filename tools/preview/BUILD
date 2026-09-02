# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

package(default_visibility = ["//visibility:public"])

exports_files([
    "provision-preview.sh",
    "neon-branch.sh",
    "pr-comment.sh",
])

sh_binary(
    name = "neon-branch",
    srcs = ["neon-branch.sh"],
)

sh_test(
    name = "neon-branch_test",
    size = "small",
    srcs = ["neon-branch_test.sh"],
    args = ["$(location :neon-branch.sh)"],
    data = [":neon-branch.sh"],
)

sh_binary(
    name = "provision-preview",
    srcs = ["provision-preview.sh"],
    data = [
        ":neon-branch",
        ":pr-comment",
    ],
)

sh_test(
    name = "provision-preview_test",
    size = "small",
    srcs = ["provision-preview_test.sh"],
    args = ["$(location :provision-preview.sh)"],
    data = [
        ":neon-branch.sh",
        ":pr-comment.sh",
        ":provision-preview.sh",
    ],
)

sh_binary(
    name = "pr-comment",
    srcs = ["pr-comment.sh"],
)

sh_test(
    name = "pr-comment_test",
    size = "small",
    srcs = ["pr-comment_test.sh"],
    args = ["$(location :pr-comment.sh)"],
    data = [":pr-comment.sh"],
)
