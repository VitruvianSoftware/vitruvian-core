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
    ],
    crate_name = "envoyproxy",
    edition = "2021",
    deps = [
        "//tools/gitops/values-yaml:values_yaml",
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

# The pinned HTTP nodePort, read by //gitops/argocd/platform/headscale's test so
# the Headscale ACL and the CI Zitadel tunnel cannot drift from it.
exports_files(
    ["gateway/envoyproxy.yaml"],
    visibility = ["//gitops/argocd/platform/headscale:__pkg__"],
)
