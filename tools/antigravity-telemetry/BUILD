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

"""Antigravity & AGY OTLP Telemetry Exporter, Hooks, and Developer Tooling."""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# ----------------------------------------------------------------------------
# Native Rust implementation (src/) — primary binary (`:antigravity-telemetry`).
# Hand-written: Gazelle has no Rust here. std only:
# it does its own JSON (src/json.rs says why serde_json, with the features
# @crates enables, sorts keys and misparses some floats), so Cargo.toml,
# Cargo.lock and MODULE.bazel stay as they are.
# ----------------------------------------------------------------------------

rust_library(
    name = "antigravity_telemetry_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
)

# One binary for every entry point: `setup`, `status`, `emit`, `export`,
# `session-exporter`, `telemetry-hook`, `telemetry-loader`.
rust_binary(
    name = "antigravity-telemetry",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":antigravity_telemetry_lib"],
)

alias(
    name = "antigravity_telemetry",
    actual = ":antigravity-telemetry",
    visibility = ["//visibility:public"],
)

alias(
    name = "antigravity-telemetry-rs",
    actual = ":antigravity-telemetry",
    visibility = ["//visibility:public"],
)

alias(
    name = "antigravity_telemetry_rs",
    actual = ":antigravity-telemetry",
    visibility = ["//visibility:public"],
)

rust_binary(
    name = "session-exporter",
    srcs = ["src/main.rs"],
    args = ["session-exporter"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":antigravity_telemetry_lib"],
)

alias(
    name = "session_exporter",
    actual = ":session-exporter",
    visibility = ["//visibility:public"],
)

rust_binary(
    name = "telemetry-hook",
    srcs = ["src/main.rs"],
    args = ["telemetry-hook"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":antigravity_telemetry_lib"],
)

alias(
    name = "telemetry_hook",
    actual = ":telemetry-hook",
    visibility = ["//visibility:public"],
)

rust_binary(
    name = "telemetry-loader",
    srcs = ["src/main.rs"],
    args = ["telemetry-loader"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":antigravity_telemetry_lib"],
)

alias(
    name = "telemetry_loader",
    actual = ":telemetry-loader",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "antigravity_telemetry_lib_test",
    size = "small",
    crate = ":antigravity_telemetry_lib",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "telemetry_rs_test",
    tests = [":antigravity_telemetry_lib_test"],
)

test_suite(
    name = "telemetry_test",
    tests = [":antigravity_telemetry_lib_test"],
)

test_suite(
    name = "antigravity_telemetry_test",
    tests = [":antigravity_telemetry_lib_test"],
)
