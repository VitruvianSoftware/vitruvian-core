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

"""Detect duplicated shared-package code from git history.

  bazel run //tools/dupcheck -- --diff <base>...<head> [--strict] [--allow <glob>...]
  bazel run //tools/dupcheck -- --families [--ref <commit>]
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "dupcheck_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "dupcheck",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "dupcheck",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":dupcheck_lib"],
)

rust_test(
    name = "dupcheck_lib_test",
    size = "small",
    compile_data = ["allow.txt"],
    crate = ":dupcheck_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "dupcheck_test",
    tests = [":dupcheck_lib_test"],
)
