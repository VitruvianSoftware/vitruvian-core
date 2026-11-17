# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Python's string, json and argparse behaviour for the Rust ports of Python tools.

No third-party crates, so any tool can link it whatever crate hub it uses.
"""

load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")

rust_library(
    name = "vitruvian_pycompat",
    srcs = glob(["src/**/*.rs"]),
    crate_name = "vitruvian_pycompat",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
)

rust_test(
    name = "vitruvian_pycompat_test",
    size = "small",
    crate = ":vitruvian_pycompat",
)
