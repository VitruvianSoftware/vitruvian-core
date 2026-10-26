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

# //tools/pipeline/gen: writes .github/workflows/presubmit.yaml (and the
# dynamic matrix) from the pipeline_unit() declarations in BUILD files.
#
#   bazel run //tools/pipeline:gen -- --format=workflow --output-file=.github/workflows/presubmit.yaml [--check]
#
# `:gen` is the Rust port (src/); the Go original stays as `:gen-go` and
# `:gen_test` still tests its library. The parity test runs both binaries
# over the same inputs and requires the same stdout, stderr, written files
# and exit code. src/unitfile.rs and src/actionpins.rs carry copies of
# //tools/pipeline/unitfile and //tools/ci/actionpins, which stay the Go
# source of truth (the presubmit planner still uses unitfile).
#
# Hand-written: gazelle would add a second `gen` go_binary.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

package(default_visibility = ["//visibility:public"])

go_library(
    name = "gen_lib",
    srcs = [
        "dag.go",
        "main.go",
        "matrix.go",
        "render.go",
        "unit.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/pipeline/gen",
    deps = [
        "//tools/ci/actionpins",
        "//tools/pipeline/unitfile",
    ],
)

go_binary(
    name = "gen-go",
    data = ["//:pins_manifest"],
    embed = [":gen_lib"],
    visibility = ["//visibility:public"],
)

go_test(
    name = "gen_test",
    srcs = [
        "main_test.go",
        "runner_test.go",
    ],
    data = glob([
        "testdata/**",
    ]) + [
        "//:pins_manifest",
    ],
    embed = [":gen_lib"],
    deps = ["//tools/ci/actionpins"],
)

# The Rust port. serde_json writes the matrix and units JSON (with Go's
# HTML escaping on top); src/gojson.rs reads .pipeline.json with Go's
# decoding rules and error text. Optimised in every build mode.
rust_library(
    name = "gen_rs_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "pipeline_gen",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "gen",
    srcs = ["src/main.rs"],
    data = ["//:pins_manifest"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":gen_rs_lib"],
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
    name = "gen_rs_lib_test",
    size = "small",
    crate = ":gen_rs_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# :gen against :gen-go: the real repository's presubmit.yaml, every
# testdata fixture, the scenarios of main_test.go and runner_test.go as
# unit files and BUILD trees, and flag and error cases. stdout, stderr
# (argv[0] masked in usage text), every written file and the exit code must
# be identical.
py_test(
    name = "gen_rs_parity_test",
    size = "medium",
    srcs = ["gen_rs_parity_test.py"],
    data = glob(["testdata/**"]) + [
        ":gen",
        ":gen-go",
        "//:pins_manifest",
    ],
    env = {
        "GEN_GO": "$(rootpath :gen-go)",
        "GEN_RS": "$(rootpath :gen)",
    },
    main = "gen_rs_parity_test.py",
)
