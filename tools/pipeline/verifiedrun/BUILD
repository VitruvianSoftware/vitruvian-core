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

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# `bazel run //tools/pipeline/verifiedrun` -- runs a change's PR tests on the
# remote build machines and records a pass against the exact code (#3418).
# See README.md.

rust_library(
    name = "pipeline_verifiedrun_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "verifiedrun",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/pipeline/unitfile:unitfile_lib",
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "verifiedrun",
    srcs = ["src/main.rs"],
    args = [
        "--planner=$(rlocationpath //tools/pipeline/plan)",
        "--affected-targets=$(rlocationpath //tools/ci:affected_targets)",
        "--rdeps-map-ref=$(rlocationpath //tools/ci:rdeps_map_ref)",
        "--agent-app=$(rlocationpath //tools/agent-app:agent-app.sh)",
    ],
    data = [
        "//tools/agent-app",
        "//tools/agent-app:agent-app.sh",
        "//tools/ci:affected_targets",
        "//tools/ci:rdeps_map_ref",
        "//tools/pipeline/plan",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":pipeline_verifiedrun_lib",
        "//tools/pipeline/unitfile:unitfile_lib",
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_test(
    name = "verifiedrun_test",
    size = "small",
    crate = ":pipeline_verifiedrun_lib",
    data = ["recorder.tsv"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "pipeline_verifiedrun_lib_test",
    tests = [":verifiedrun_test"],
)
