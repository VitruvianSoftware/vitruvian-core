# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Go standard-library behaviour for Rust ports of Go tools.

No third-party crates, so any tool can link it whatever crate hub it uses.
"""

load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")

rust_library(
    name = "vitruvian_gocompat",
    srcs = glob(["src/**/*.rs"]),
    crate_name = "vitruvian_gocompat",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
)

rust_test(
    name = "vitruvian_gocompat_test",
    size = "small",
    crate = ":vitruvian_gocompat",
)
