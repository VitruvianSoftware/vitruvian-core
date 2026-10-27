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

# The delivery workflow generator (spec §4.3). Run it as //tools/ci:gen (the
# alias the spec and tidy-check name); this is the implementation.
#
#   bazel run //tools/ci:gen
#
# Public visibility is required by the //tools/ci:gen alias, which lives in a
# different package.
# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "delivery_gen_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "delivery_gen",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

alias(
    name = "gen_rs_lib",
    actual = ":delivery_gen_lib",
)

rust_binary(
    name = "gen",
    srcs = ["src/main.rs"],
    data = ["//:pins_manifest"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":delivery_gen_lib"],
)

alias(
    name = "gen-rs",
    actual = ":gen",
    visibility = ["//visibility:public"],
)

alias(
    name = "gen_rs",
    actual = ":gen",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "gen_test",
    size = "small",
    crate = ":delivery_gen_lib",
    data = glob(["testdata/**"]),
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "delivery_gen_lib_test",
    tests = [":gen_test"],
)

test_suite(
    name = "gen_rs_lib_test",
    tests = [":gen_test"],
)
