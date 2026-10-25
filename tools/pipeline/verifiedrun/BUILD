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

# Hand-written: gazelle would rename the Go binary back to :verifiedrun and
# not generate the Rust targets.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# `bazel run //tools/pipeline/verifiedrun` -- runs a change's PR tests on the
# remote build machines and records a pass against the exact code (#3418).
# See README.md.

go_library(
    name = "verifiedrun_lib",
    srcs = [
        "main.go",
        "record.go",
        "shim.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/pipeline/verifiedrun",
    visibility = ["//visibility:private"],
    deps = ["//tools/pipeline/unitfile"],
)

# The Go tool, kept for the parity test and as a fallback:
# `bazel run //tools/pipeline/verifiedrun:verifiedrun-go`.
go_binary(
    name = "verifiedrun-go",
    args = [
        "--planner=$(rlocationpath //tools/pipeline/plan)",
        "--agent-app=$(rlocationpath //tools/agent-app:agent-app.sh)",
    ],
    data = [
        "//tools/agent-app:agent-app.sh",
        "//tools/pipeline/plan",
    ],
    embed = [":verifiedrun_lib"],
    visibility = ["//visibility:public"],
)

go_test(
    name = "verifiedrun_test",
    size = "small",
    srcs = [
        "main_test.go",
        "record_test.go",
        "shim_test.go",
    ],
    data = ["recorder.tsv"],
    embed = [":verifiedrun_lib"],
    deps = ["//tools/pipeline/unitfile"],
)

# The Rust port (src/): the default :verifiedrun. Same flags, output, exit
# codes, bazel command lines and record as :verifiedrun-go; the binary is
# also its own bazel wrapper (`verifiedrun __shim ...`). The planner it runs
# is :plan, the Rust planner. Optimised in every build mode.
rust_library(
    name = "verifiedrun_rs_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "verifiedrun",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/pipeline/unitfile:unitfile_rs_lib",
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "verifiedrun",
    srcs = ["src/main.rs"],
    args = [
        "--planner=$(rlocationpath //tools/pipeline/plan)",
        "--agent-app=$(rlocationpath //tools/agent-app:agent-app.sh)",
    ],
    data = [
        "//tools/agent-app:agent-app.sh",
        "//tools/pipeline/plan",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":verifiedrun_rs_lib",
        "//tools/pipeline/unitfile:unitfile_rs_lib",
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

alias(
    name = "verifiedrun-rs",
    actual = ":verifiedrun",
    visibility = ["//visibility:public"],
)

alias(
    name = "verifiedrun_rs",
    actual = ":verifiedrun",
    visibility = ["//visibility:public"],
)

# main_test.go, record_test.go and shim_test.go, against the Rust port.
rust_test(
    name = "verifiedrun_rs_lib_test",
    size = "small",
    crate = ":verifiedrun_rs_lib",
    data = ["recorder.tsv"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# :verifiedrun-go and :verifiedrun side by side over scratch repos with an
# origin, a fake bazel, fake planner and agent-app, and every refusal: stdout,
# stderr, exit code, every bazel command line, planner and token call, and
# the files left behind must match.
py_test(
    name = "verifiedrun_rs_parity_test",
    size = "medium",
    srcs = ["verifiedrun_rs_parity_test.py"],
    data = [
        ":verifiedrun",
        ":verifiedrun-go",
        "//tools/pipeline/plan",
        "//tools/pipeline/plan:plan-go",
    ],
    env = {
        "PLAN_GO": "$(rootpath //tools/pipeline/plan:plan-go)",
        "PLAN_RS": "$(rootpath //tools/pipeline/plan)",
        "VERIFIEDRUN_GO": "$(rootpath :verifiedrun-go)",
        "VERIFIEDRUN_RS": "$(rootpath :verifiedrun)",
    },
    main = "verifiedrun_rs_parity_test.py",
)
