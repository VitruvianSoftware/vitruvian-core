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
# `:orchestrate` is the Rust port (src/); the Go original stays as
# `:orchestrate-go`, and `:orchestrate_test` still tests its library. The
# parity test runs both binaries over the same scratch repos, fake bazel and
# real deploy-affected.sh, and requires the same exit code, stdout, stderr,
# manifest bytes and $GITHUB_OUTPUT bytes.
#
# Hand-written: gazelle would add a second `orchestrate` go_binary.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

go_library(
    name = "orchestrate_lib",
    srcs = ["main.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/delivery/orchestrate",
    visibility = ["//visibility:private"],
)

go_binary(
    name = "orchestrate-go",
    embed = [":orchestrate_lib"],
    visibility = ["//visibility:public"],
)

go_test(
    name = "orchestrate_test",
    size = "small",
    srcs = ["main_test.go"],
    # The decision engine is NOT stubbed: these tests drive the real
    # tools/ci/deploy-affected.sh over scratch git repos, so it (and the
    # td-lib.sh it sources) must be in the runfiles. rules_go runs the test
    # from its own package dir, so the test's "../../ci/..." path resolves
    # against the runfiles copy under bazel test and against the checkout
    # under a plain `GOWORK=off go test ./...`.
    data = [
        "//tools/ci:deploy-affected.sh",
        "//tools/ci:td-lib.sh",
    ],
    embed = [":orchestrate_lib"],
)

# The Rust port. serde derives the manifest and serde_json writes it (with
# Go's HTML escaping); src/json.rs reads metadata with Go's scanner so a
# fail-open reason quotes Go's decoder error word for word. Optimised in
# every build mode.
rust_library(
    name = "orchestrate_rs_lib",
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
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":orchestrate_rs_lib"],
)

alias(
    name = "orchestrate-rs",
    actual = ":orchestrate",
    visibility = ["//visibility:public"],
)

alias(
    name = "orchestrate_rs",
    actual = ":orchestrate",
    visibility = ["//visibility:public"],
)

# main_test.go's cases, against the Rust library and the same real engine.
rust_test(
    name = "orchestrate_rs_lib_test",
    size = "small",
    crate = ":orchestrate_rs_lib",
    data = [
        "//tools/ci:deploy-affected.sh",
        "//tools/ci:td-lib.sh",
    ],
    edition = "2021",
    env = {"DEPLOY_AFFECTED": "$(rootpath //tools/ci:deploy-affected.sh)"},
    rustc_flags = ["-Copt-level=3"],
)

# :orchestrate against :orchestrate-go: every main_test.go scenario (the real
# deploy-affected.sh over scratch git repos, a fake bazel), the CLI flags and
# the error paths. Exit code, stdout, stderr, manifest and GITHUB_OUTPUT must
# be byte-identical.
py_test(
    name = "orchestrate_rs_parity_test",
    size = "medium",
    srcs = ["orchestrate_rs_parity_test.py"],
    data = [
        ":orchestrate",
        ":orchestrate-go",
        "//tools/ci:deploy-affected.sh",
        "//tools/ci:td-lib.sh",
    ],
    env = {
        "DEPLOY_AFFECTED": "$(rootpath //tools/ci:deploy-affected.sh)",
        "ORCHESTRATE_GO": "$(rootpath :orchestrate-go)",
        "ORCHESTRATE_RS": "$(rootpath :orchestrate)",
        "TD_LIB": "$(rootpath //tools/ci:td-lib.sh)",
    },
    main = "orchestrate_rs_parity_test.py",
)
