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

"""Android Wireless Debugging auto-discovery and connection tool."""

# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_library", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

py_library(
    name = "lib",
    srcs = ["adb_connect.py"],
    imports = ["."],
    visibility = ["//visibility:public"],
)

py_binary(
    name = "adb-connect-py",
    srcs = ["adb_connect.py"],
    imports = ["."],
    main = "adb_connect.py",
    visibility = ["//visibility:public"],
    deps = [":lib"],
)

py_test(
    name = "adb_connect_test",
    size = "small",
    srcs = ["adb_connect_test.py"],
    imports = ["."],
    main = "adb_connect_test.py",
    deps = [
        ":lib",
    ],
)

# --- Rust port (primary binary) ----------------------------------------------
# src/ is a line-for-line port of adb_connect.py: same flags, help text,
# output, JSON and exit codes. It needs only Rust std (it carries its own
# Python-compatible json and argparse so messages match byte for byte), so
# it adds no crate and Cargo.lock / MODULE.bazel stay as they are.

rust_library(
    name = "adb_connect_lib",
    srcs = glob(
        ["src/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
)

rust_binary(
    name = "adb-connect",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":adb_connect_lib"],
)

alias(
    name = "adb_connect",
    actual = ":adb-connect",
    visibility = ["//visibility:public"],
)

alias(
    name = "adb_connect_rs",
    actual = ":adb-connect",
    visibility = ["//visibility:public"],
)

# The #[cfg(test)] unit tests in src/, against a scripted System (the
# Python tests' cases plus parser, json, argparse and textwrap checks).
rust_test(
    name = "adb_connect_lib_test",
    size = "small",
    crate = ":adb_connect_lib",
    rustc_flags = ["-Copt-level=3"],
)

# adb_connect.py and adb-connect (Rust) run side by side against the same
# stand-in adb / dns-sd / tailscale programs: stdout, stderr, exit code,
# the commands each one ran, and the files they read must all match.
py_test(
    name = "adb_connect_rs_parity_test",
    size = "small",
    srcs = ["adb_connect_rs_parity_test.py"],
    args = [
        "$(rootpath :adb-connect)",
        "$(rootpath adb_connect.py)",
    ],
    data = [
        "adb_connect.py",
        ":adb-connect",
    ],
    main = "adb_connect_rs_parity_test.py",
)
