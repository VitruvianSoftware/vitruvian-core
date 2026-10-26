# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")
load("//tools/gitops:defs.bzl", "gitops_manifest")

# gazelle:ignore

gitops_manifest(
    name = "prometheus",
    manifests = ["applicationset.yaml"],
)

rust_library(
    name = "prometheus_values_lib",
    srcs = [
        "src/lib.rs",
        "src/yaml.rs",
    ],
    crate_name = "prometheus_values",
    edition = "2021",
    deps = [
        "@crates//:serde_json",
    ],
)

rust_test(
    name = "prometheus_values_test",
    size = "small",
    crate = ":prometheus_values_lib",
    data = ["applicationset.yaml"],
    edition = "2021",
)

alias(
    name = "prometheus_values_rs_test",
    actual = ":prometheus_values_test",
)

py_test(
    name = "prometheus_values_py_test",
    size = "small",
    srcs = ["prometheus_values_test.py"],
    data = ["applicationset.yaml"],
    main = "prometheus_values_test.py",
    deps = ["@pip//pyyaml"],
)
