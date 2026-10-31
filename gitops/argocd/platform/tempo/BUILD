# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

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
