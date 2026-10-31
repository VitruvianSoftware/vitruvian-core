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

# The repo version-conformance checker: `bazel run //tools/conformance:check`.
# Reads the live source tree via BUILD_WORKSPACE_DIRECTORY, checking that every
# go.mod / Dockerfile-node / package.json matches the repo's canonical version,
# with deviations allowed only as justified temporary pins in version-pins.tsv.
# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "conformance_check",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "conformance_check",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//tools:__subpackages__"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "check",
    srcs = ["src/main.rs"],
    data = [
        "delivery-legacy.tsv",
        "version-pins.tsv",
        "//tools/copybara:check-version-maps",
        "//tools/owners",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":conformance_check",
    ],
)

rust_test(
    name = "conformance_check_test",
    size = "small",
    crate = ":conformance_check",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

[
    test_suite(
        name = test_name,
        tests = [":conformance_check_test"],
    )
    for test_name in [
        "check_test",
        "conformance-delivery_test",
        "conformance-owners_test",
    ]
]
