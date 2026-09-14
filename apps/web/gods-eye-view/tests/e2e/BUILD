# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

package(default_visibility = ["//visibility:public"])

sh_binary(
    name = "runner",
    srcs = ["run-e2e-tests.sh"],
    data = [
        ":tier1_feature_test.sh",
        ":tier2_boundary_test.sh",
        ":tier3_combination_test.sh",
        ":tier4_scenario_test.sh",
        ":tier5_adversarial_test.sh",
    ],
)

sh_test(
    name = "tier1_feature_test",
    size = "medium",
    srcs = ["tier1_feature_test.sh"],
    tags = [
        "local",
        "manual",
    ],
)

sh_test(
    name = "tier2_boundary_test",
    size = "medium",
    srcs = ["tier2_boundary_test.sh"],
    tags = [
        "local",
        "manual",
    ],
)

sh_test(
    name = "tier3_combination_test",
    size = "medium",
    srcs = ["tier3_combination_test.sh"],
    tags = [
        "local",
        "manual",
    ],
)

sh_test(
    name = "tier4_scenario_test",
    size = "medium",
    srcs = ["tier4_scenario_test.sh"],
    tags = [
        "local",
        "manual",
    ],
)

sh_test(
    name = "tier5_adversarial_test",
    size = "medium",
    srcs = ["tier5_adversarial_test.sh"],
    tags = [
        "local",
        "manual",
    ],
)

sh_test(
    name = "run_e2e_tests",
    size = "large",
    srcs = ["run-e2e-tests.sh"],
    data = [
        ":tier1_feature_test.sh",
        ":tier2_boundary_test.sh",
        ":tier3_combination_test.sh",
        ":tier4_scenario_test.sh",
        ":tier5_adversarial_test.sh",
    ],
    tags = [
        "local",
        "manual",
    ],
)
