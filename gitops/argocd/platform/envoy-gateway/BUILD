# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")
load("//tools/gitops:defs.bzl", "gitops_manifest")

# gazelle:ignore

gitops_manifest(
    name = "envoy-gateway",
    manifests = ["applicationset.yaml"],
)

rust_library(
    name = "envoyproxy_lib",
    srcs = [
        "src/lib.rs",
        "src/yaml.rs",
    ],
    crate_name = "envoyproxy",
    edition = "2021",
    deps = [
        "@crates//:serde_json",
    ],
)

rust_test(
    name = "envoyproxy_test",
    size = "small",
    crate = ":envoyproxy_lib",
    data = ["gateway/envoyproxy.yaml"],
    edition = "2021",
)
