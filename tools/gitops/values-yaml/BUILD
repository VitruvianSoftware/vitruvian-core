# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""The YAML reader the gitops/argocd/platform/* value tests share.

It parses YAML into serde_json::Value and finds a test's data files in its
runfiles. It used to be copied into each platform package's src/yaml.rs.
"""

load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")

rust_library(
    name = "values_yaml",
    srcs = ["src/lib.rs"],
    crate_name = "gitops_values_yaml",
    edition = "2021",
    visibility = ["//gitops/argocd/platform:__subpackages__"],
    deps = ["@crates//:serde_json"],
)

rust_test(
    name = "values_yaml_test",
    size = "small",
    crate = ":values_yaml",
    edition = "2021",
)
