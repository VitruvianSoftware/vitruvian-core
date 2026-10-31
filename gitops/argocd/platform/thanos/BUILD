# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")
load("//tools/gitops:defs.bzl", "gitops_manifest")

# gazelle:ignore

gitops_manifest(
    name = "thanos",
    manifests = ["applicationset.yaml"],
)

rust_library(
    name = "thanos_values_lib",
    srcs = [
        "src/lib.rs",
        "src/yaml.rs",
    ],
    crate_name = "thanos_values",
    edition = "2021",
    deps = [
        "@crates//:serde_json",
    ],
)

rust_test(
    name = "thanos_values_test",
    size = "small",
    crate = ":thanos_values_lib",
    data = ["applicationset.yaml"],
    edition = "2021",
)
