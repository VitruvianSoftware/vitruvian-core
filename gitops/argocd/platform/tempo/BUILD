# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")
load("//tools/gitops:defs.bzl", "gitops_manifest")

# gazelle:ignore

gitops_manifest(
    name = "tempo",
    manifests = ["applicationset.yaml"],
)

rust_library(
    name = "tempo_values_lib",
    srcs = [
        "src/lib.rs",
        "src/yaml.rs",
    ],
    crate_name = "tempo_values",
    edition = "2021",
    deps = [
        "@crates//:serde_json",
    ],
)

rust_test(
    name = "tempo_values_test",
    size = "small",
    crate = ":tempo_values_lib",
    data = ["applicationset.yaml"],
    edition = "2021",
)

alias(
    name = "tempo_values_rs_test",
    actual = ":tempo_values_test",
)

py_test(
    name = "tempo_values_py_test",
    size = "small",
    srcs = ["tempo_values_test.py"],
    data = ["applicationset.yaml"],
    main = "tempo_values_test.py",
    deps = ["@pip//pyyaml"],
)
