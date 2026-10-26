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

# Guards the shared Maven lock file against placeholder-version artifacts --
# published jars that deliberately contain no classes.

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

rust_library(
    name = "no_empty_placeholder_jars_lib",
    srcs = ["src/lib.rs"],
    crate_name = "no_empty_placeholder_jars_lib",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["@rules_rust//rust/runfiles"],
)

rust_binary(
    name = "no-empty-placeholder-jars-bin",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":no_empty_placeholder_jars_lib"],
)

alias(
    name = "no_empty_placeholder_jars_bin",
    actual = ":no-empty-placeholder-jars-bin",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "no_empty_placeholder_jars_lib_test",
    size = "small",
    crate = ":no_empty_placeholder_jars_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

sh_test(
    name = "no_empty_placeholder_jars_test",
    size = "small",
    srcs = [":no-empty-placeholder-jars-bin"],
    data = ["//:maven_install.json"],
    env = {
        "LOCK_FILE": "$(rlocationpath //:maven_install.json)",
    },
)

test_suite(
    name = "no_empty_placeholder_jars",
    tests = [
        ":no_empty_placeholder_jars_lib_test",
        ":no_empty_placeholder_jars_test",
    ],
)
