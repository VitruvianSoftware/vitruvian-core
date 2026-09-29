# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("@aspect_rules_py//py:defs.bzl", "py_test")

filegroup(
    name = "manifests",
    srcs = glob(["*.yaml"]),
    visibility = ["//visibility:public"],
)

py_test(
    name = "collector_config_test",
    size = "small",
    srcs = ["collector_config_test.py"],
    data = [
        "collector.yaml",
        "//gitops/argocd/applications:cicd-telemetry.yaml",
    ],
    main = "collector_config_test.py",
    deps = ["@pip//pyyaml"],
)
