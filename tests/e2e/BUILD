# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

package(default_visibility = ["//visibility:public"])

sh_binary(
    name = "runner",
    srcs = ["runner.sh"],
    data = [
        ":tier1_feature_test.sh",
        ":tier2_boundary_test.sh",
        ":tier3_combination_test.sh",
        ":tier4_workload_test.sh",
        "//tools/owners",
        "//tools/pipeline/gen",
        "//tools/pipeline/plan",
    ],
)

sh_test(
    name = "tier1_feature_test",
    size = "medium",
    srcs = ["tier1_feature_test.sh"],
    data = [
        "//tools/boundaries:package_groups.bzl",
        "//tools/lint:boundaries.bzl",
        "//tools/owners",
        "//tools/pipeline/gen",
        "//tools/pipeline/plan",
    ],
)

sh_test(
    name = "tier2_boundary_test",
    size = "medium",
    srcs = ["tier2_boundary_test.sh"],
    data = [
        "//tools/boundaries:package_groups.bzl",
        "//tools/lint:boundaries.bzl",
        "//tools/owners",
        "//tools/pipeline/gen",
        "//tools/pipeline/plan",
    ],
)

sh_test(
    name = "tier3_combination_test",
    size = "medium",
    srcs = ["tier3_combination_test.sh"],
    data = [
        "//tools/owners",
        "//tools/pipeline/gen",
        "//tools/pipeline/plan",
    ],
)

sh_test(
    name = "tier4_workload_test",
    size = "medium",
    srcs = ["tier4_workload_test.sh"],
    data = [
        "//tools/boundaries:package_groups.bzl",
        "//tools/lint:boundaries.bzl",
        "//tools/owners",
        "//tools/pipeline/gen",
        "//tools/pipeline/plan",
    ],
)

sh_test(
    name = "runner_test",
    size = "large",
    srcs = ["runner.sh"],
    data = [
        ":tier1_feature_test.sh",
        ":tier2_boundary_test.sh",
        ":tier3_combination_test.sh",
        ":tier4_workload_test.sh",
        "//tools/owners",
        "//tools/pipeline/gen",
        "//tools/pipeline/plan",
    ],
)
