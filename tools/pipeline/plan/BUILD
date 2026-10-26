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

# Hand-written: gazelle would rename the Go binary back to :plan and not
# generate the Rust targets.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

package(default_visibility = ["//visibility:public"])

go_library(
    name = "plan_lib",
    srcs = [
        "classifier.go",
        "diff.go",
        "engine.go",
        "gates.go",
        "main.go",
        "packages.go",
        "plan.go",
        "query.go",
        "rdepsmap.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/pipeline/plan",
    visibility = ["//visibility:private"],
    deps = ["//tools/pipeline/unitfile"],
)

# The Go planner, kept for the parity test and as a fallback.
go_binary(
    name = "plan-go",
    embed = [":plan_lib"],
    visibility = ["//visibility:public"],
)

go_test(
    name = "plan_test",
    srcs = [
        "plan_test.go",
        "rdepsmap_test.go",
        "units_test.go",
    ],
    embed = [":plan_lib"],
)

# The Rust port (src/): the default :plan. Same flags, output, messages and
# exit codes as :plan-go; plan_rs_parity_test runs the two side by side.
# Optimised in every build mode.
rust_library(
    name = "plan_rs_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "plan",
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
    name = "plan",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":plan_rs_lib",
        "//tools/pipeline/unitfile:unitfile_rs_lib",
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

alias(
    name = "plan-rs",
    actual = ":plan",
    visibility = ["//visibility:public"],
)

alias(
    name = "plan_rs",
    actual = ":plan",
    visibility = ["//visibility:public"],
)

# plan_test.go, rdepsmap_test.go and units_test.go, against the Rust port.
rust_test(
    name = "plan_rs_lib_test",
    size = "small",
    crate = ":plan_rs_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# :plan-go and :plan side by side over scratch git repos, a fake bazel and
# every flag and failure path: stdout, stderr, exit code, GITHUB_OUTPUT and
# written files must match.
py_test(
    name = "plan_rs_parity_test",
    size = "medium",
    srcs = ["plan_rs_parity_test.py"],
    data = [
        ":plan",
        ":plan-go",
        "//tools/pipeline/unitfile:real_units",
    ],
    env = {
        "PLAN_GO": "$(rootpath :plan-go)",
        "PLAN_RS": "$(rootpath :plan)",
    },
    main = "plan_rs_parity_test.py",
)
