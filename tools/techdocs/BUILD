# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# gazelle:ignore

# `bazel run //tools/techdocs:check` -- build every mkdocs.yml site with
# mkdocs-techdocs-core, as Backstage does.
rust_library(
    name = "techdocs_lib",
    srcs = ["src/lib.rs"],
    crate_name = "techdocs",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_binary(
    name = "check",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":techdocs_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[
    alias(
        name = name,
        actual = ":check",
        visibility = ["//visibility:public"],
    )
    for name in [
        "check-rs",
        "check_rs",
    ]
]

rust_test(
    name = "techdocs_lib_test",
    size = "small",
    crate = ":techdocs_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)
