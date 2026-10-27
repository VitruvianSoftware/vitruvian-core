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

rust_library(
    name = "lint_naming_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "lint_naming",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
)

rust_binary(
    name = "lint-naming",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":lint_naming_lib"],
)

alias(
    name = "lint_naming",
    actual = ":lint-naming",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "lint_naming_lib_test",
    size = "small",
    crate = ":lint_naming_lib",
    data = glob(["testdata/**/*"]),
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "lint-naming_test",
    tests = [":lint_naming_lib_test"],
    visibility = ["//visibility:public"],
)

test_suite(
    name = "lint_naming_test",
    tests = [":lint_naming_lib_test"],
    visibility = ["//visibility:public"],
)

test_suite(
    name = "tier1_feature_test",
    tests = [":lint_naming_lib_test"],
)

test_suite(
    name = "tier2_boundary_test",
    tests = [":lint_naming_lib_test"],
)

test_suite(
    name = "tier3_pairwise_test",
    tests = [":lint_naming_lib_test"],
)

test_suite(
    name = "tier4_realworld_test",
    tests = [":lint_naming_lib_test"],
)
