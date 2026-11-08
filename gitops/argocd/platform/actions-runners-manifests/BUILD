# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("@rules_rust//rust:defs.bzl", "rust_test")

# gazelle:ignore

# Runs the cache GC CronJob's own script against a fake cache, so the sweep
# can never again delete files out of Bazel's repo contents cache
# (cache-gc-cronjob.yaml, header).
rust_test(
    name = "cache_gc_test",
    size = "small",
    srcs = ["src/lib.rs"],
    crate_root = "src/lib.rs",
    data = ["cache-gc-cronjob.yaml"],
    edition = "2021",
)
