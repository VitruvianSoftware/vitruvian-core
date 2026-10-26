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

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

# gazelle:ignore

exports_files(["check.sh"])

# `bazel run //tools/techdocs:check` -- build every mkdocs.yml site with
# mkdocs-techdocs-core, as Backstage does. The tool is the Rust port in src/
# (check.sh's walk, report and exit codes, held to the script by the parity
# test below); the script stays runnable as :check-sh.
rust_library(
    name = "techdocs_lib",
    srcs = ["src/lib.rs"],
    crate_name = "techdocs",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_binary(
    name = "check",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":techdocs_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[
    alias(
        name = name,
        actual = ":check",
        visibility = ["//visibility:public"],
    )
    for name in [
        "check-rs",
        "check_rs",
    ]
]

# The shell original, kept runnable and held to the port by the parity test.
sh_binary(
    name = "check-sh",
    srcs = ["check.sh"],
    visibility = ["//visibility:public"],
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "techdocs_lib_test",
    size = "small",
    crate = ":techdocs_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Script and binary side by side on every case in check_rs_parity_test.py
# (fake git and uv): exit code, stdout, stderr, the uv calls and the site/
# directories left behind, byte for byte, under every bash on the machine.
py_test(
    name = "check_rs_parity_test",
    size = "medium",
    srcs = ["check_rs_parity_test.py"],
    data = [
        "check.sh",
        ":check",
    ],
    env = {
        "CHECK_RS": "$(rootpath :check)",
        "CHECK_SH": "$(rootpath check.sh)",
    },
    main = "check_rs_parity_test.py",
    deps = ["//tools/shell-compat:parity_harness"],
)
