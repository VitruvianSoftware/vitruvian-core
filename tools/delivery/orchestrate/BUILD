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

# //tools/delivery/orchestrate: the delivery orchestrator's DECIDE stage.
#
#   bazel run //tools/delivery/orchestrate -- --out delivery-manifest.json
#
# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "delivery_orchestrate_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "orchestrate",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "orchestrate",
    srcs = ["src/main.rs"],
    data = ["//tools/ci:deploy_affected"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":delivery_orchestrate_lib",
        "@rules_rust//rust/runfiles",
    ],
)

rust_test(
    name = "orchestrate_test",
    size = "small",
    crate = ":delivery_orchestrate_lib",
    data = ["//tools/ci:deploy_affected"],
    edition = "2021",
    env = {"DEPLOY_AFFECTED": "$(rootpath //tools/ci:deploy_affected)"},
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "delivery_orchestrate_lib_test",
    tests = [":orchestrate_test"],
)
