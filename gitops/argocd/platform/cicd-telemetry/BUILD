# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")

# gazelle:ignore

filegroup(
    name = "manifests",
    srcs = glob(["*.yaml"]),
    visibility = ["//visibility:public"],
)

DATA_FILES = [
    "collector.yaml",
    "network-policy.yaml",
    "//gitops/argocd/applications:cicd-telemetry.yaml",
]

rust_library(
    name = "collector_config_lib",
    srcs = [
        "src/lib.rs",
        "src/yaml.rs",
    ],
    crate_name = "collector_config",
    edition = "2021",
    deps = [
        "@crates//:serde_json",
    ],
)

rust_test(
    name = "collector_config_test",
    size = "small",
    crate = ":collector_config_lib",
    data = DATA_FILES,
    edition = "2021",
)

alias(
    name = "collector_config_rs_test",
    actual = ":collector_config_test",
)

py_test(
    name = "collector_config_py_test",
    size = "small",
    srcs = ["collector_config_test.py"],
    data = DATA_FILES,
    main = "collector_config_test.py",
    deps = ["@pip//pyyaml"],
)
