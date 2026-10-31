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

# //tools/sdk-codegen: writes each kit's types from the tool protocol's
# schemas (packages/vitruvian-sdk/protocol).
#
#   bazel run //tools/sdk-codegen

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# What the generator reads, and what it wrote that is committed.
INPUTS = [
    "//packages/vitruvian-sdk:generated_kit_files",
    "//packages/vitruvian-sdk:protocol_files",
]

rust_library(
    name = "sdk_codegen_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "sdk_codegen",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "sdk-codegen",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":sdk_codegen_lib"],
)

rust_test(
    name = "sdk_codegen_lib_test",
    size = "small",
    crate = ":sdk_codegen_lib",
    data = INPUTS,
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
)

test_suite(
    name = "in_sync_test",
    tests = [":sdk_codegen_lib_test"],
    visibility = ["//visibility:public"],
)

test_suite(
    name = "sdk_codegen_test",
    tests = [":sdk_codegen_lib_test"],
    visibility = ["//visibility:public"],
)
