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

# //tools/owners: compiles per-directory OWNERS files into .github/CODEOWNERS.
#
#   bazel run //tools/owners -- --out .github/CODEOWNERS
#   bazel run //tools/owners -- --check | --coverage-check | --validate-only
#
# `:owners` is the Rust port (src/); the Go original stays as `:owners-go` and
# `:owners_test` still tests its library. The parity test runs both binaries
# over the same trees and requires the same stdout, stderr, CODEOWNERS file
# and exit code.
#
# Hand-written: gazelle would add a second `owners` go_binary.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

go_library(
    name = "owners_lib",
    srcs = [
        "coverage.go",
        "engine.go",
        "main.go",
        "schema.go",
        "validate.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/owners",
    visibility = ["//visibility:private"],
    deps = [
        "@in_gopkg_yaml_v3//:yaml_v3",
    ],
)

go_binary(
    name = "owners-go",
    embed = [":owners_lib"],
    visibility = ["//visibility:public"],
)

go_test(
    name = "owners_test",
    size = "small",
    srcs = ["main_test.go"],
    embed = [":owners_lib"],
)

# The Rust port. serde decodes the parsed YAML into the schema's structs with
# the field rules yaml.v3 applied; src/yaml.rs is the reader (there is no YAML
# crate in @crates). Optimised in every build mode.
rust_library(
    name = "owners_rs_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "owners",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["@crates//:serde"],
)

rust_binary(
    name = "owners",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":owners_rs_lib"],
)

alias(
    name = "owners-rs",
    actual = ":owners",
    visibility = ["//visibility:public"],
)

alias(
    name = "owners_rs",
    actual = ":owners",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "owners_rs_lib_test",
    size = "small",
    crate = ":owners_rs_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# :owners against :owners-go over generated OWNERS trees: stdout, stderr
# (argv[0] masked, since Go's usage text names it), the written CODEOWNERS
# file and the exit code must be identical.
py_test(
    name = "owners_rs_parity_test",
    size = "medium",
    srcs = ["owners_rs_parity_test.py"],
    data = [
        ":owners",
        ":owners-go",
    ],
    env = {
        "OWNERS_GO": "$(rootpath :owners-go)",
        "OWNERS_RS": "$(rootpath :owners)",
    },
    main = "owners_rs_parity_test.py",
)
