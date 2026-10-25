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

# Hand-written: gazelle would otherwise add targets for the Python parity
# test, and the Rust targets are outside what it manages. The Go targets
# below are what gazelle generated; keep them that way when actionpins.go's
# imports change.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_go//go:def.bzl", "go_library", "go_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

go_library(
    name = "actionpins",
    srcs = ["actionpins.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/ci/actionpins",
    visibility = ["//visibility:public"],
)

go_test(
    name = "actionpins_test",
    size = "small",
    srcs = ["actionpins_test.go"],
    data = [
        "//:pins_manifest",
        "//:workflow_files",
    ],
    deps = [":actionpins"],
)

# --- The Rust port -----------------------------------------------------------
# src/ is actionpins.go in Rust: the manifest parser, Load, Lookup and
# FindDefaultPath, plus the Go test's check that generated workflows use only
# the manifest's pins, as a command. Everything is bytes, as Go strings are;
# src/goprint.rs (from `goprobe print-tables`) is what Go's %q counts as
# printable and strings.TrimSpace as space. The Go library stays: the
# workflow generators (//tools/delivery/gen, //tools/pipeline/gen) link it.
rust_library(
    name = "actionpins_rs_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "actionpins",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

#   bazel run //tools/ci/actionpins:actionpins-rs -- check
rust_binary(
    name = "actionpins-rs",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":actionpins_rs_lib"],
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "actionpins_rs_lib_test",
    size = "small",
    crate = ":actionpins_rs_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# actionpins-rs against the Go package (through goprobe, which calls it):
# the real manifest and workflows, then thousands of synthetic and mutated
# `uses:` lines, manifests and workflow trees, scanner-limit lines, file
# errors and default-path lookups. Exit codes, stdout and stderr must match
# byte for byte, and goprint.rs must be what goprobe generates.
py_test(
    name = "actionpins_rs_parity_test",
    size = "medium",
    srcs = ["actionpins_rs_parity_test.py"],
    data = [
        "src/goprint.rs",
        ":actionpins-rs",
        "//:pins_manifest",
        "//:workflow_files",
        "//tools/ci/actionpins/goprobe",
    ],
    env = {
        "ACTIONPINS_GO": "$(rootpath //tools/ci/actionpins/goprobe)",
        "ACTIONPINS_RS": "$(rootpath :actionpins-rs)",
        "PINS_MANIFEST": "$(rootpath //:pins_manifest)",
        "WORKFLOW_FILES": "$(rootpaths //:workflow_files)",
    },
    main = "actionpins_rs_parity_test.py",
)
