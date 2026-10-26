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

# Guards the shared Maven lock file against placeholder-version artifacts --
# published jars that deliberately contain no classes. See
# no_empty_placeholder_jars.sh for the full rationale; in short, one of these
# silently shipped an Android APK that crashed on launch on every device while
# every CI lane stayed green.

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["no_empty_placeholder_jars.sh"])

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
    name = "no_empty_placeholder_jars_bin",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":no_empty_placeholder_jars_lib"],
)

rust_test(
    name = "no_empty_placeholder_jars_lib_test",
    size = "small",
    crate = ":no_empty_placeholder_jars_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

sh_test(
    name = "no_empty_placeholder_jars",
    size = "small",
    srcs = [":no_empty_placeholder_jars_bin"],
    data = ["//:maven_install.json"],
    env = {
        "LOCK_FILE": "$(rlocationpath //:maven_install.json)",
    },
)

sh_test(
    name = "no_empty_placeholder_jars_sh_test",
    size = "small",
    srcs = ["no_empty_placeholder_jars.sh"],
    data = ["//:maven_install.json"],
    env = {
        "LOCK_FILE": "$(rlocationpath //:maven_install.json)",
    },
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

sh_test(
    name = "no_empty_placeholder_jars_parity_test",
    size = "small",
    srcs = ["no-empty-placeholder-jars-parity_test.sh"],
    data = [
        "no_empty_placeholder_jars.sh",
        ":no_empty_placeholder_jars_bin",
        "//:maven_install.json",
    ],
    env = {
        "REAL_LOCK_FILE": "$(rlocationpath //:maven_install.json)",
        "RS_TOOL": "$(rlocationpath :no_empty_placeholder_jars_bin)",
        "SH_TOOL": "$(rlocationpath no_empty_placeholder_jars.sh)",
    },
    deps = ["@bazel_tools//tools/bash/runfiles"],
)
