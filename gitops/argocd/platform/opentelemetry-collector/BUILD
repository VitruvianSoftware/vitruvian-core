# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")
load("//tools/gitops:defs.bzl", "gitops_manifest")

# gazelle:ignore

gitops_manifest(
    name = "opentelemetry-collector",
    manifests = ["applicationset.yaml"],
)

rust_library(
    name = "component_names_lib",
    srcs = [
        "src/lib.rs",
        "src/yaml.rs",
    ],
    crate_name = "component_names",
    edition = "2021",
    deps = [
        "@crates//:serde_json",
    ],
)

rust_test(
    name = "component_names_test",
    size = "small",
    crate = ":component_names_lib",
    data = ["applicationset.yaml"],
    edition = "2021",
)

alias(
    name = "component_names_rs_test",
    actual = ":component_names_test",
)
