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

# `bazel run //tools/rotate-buildbuddy-key` — guided BuildBuddy API-key rotation
# (issue #456). Automates the non-secret steps; prompts the operator to mint the
# new key and revoke the old one in the BuildBuddy console. The new value is read
# without echo and piped to `gh secret set` over stdin — never printed or logged.
#
# :rotate-buildbuddy-key is the Rust port (src/); rotate.sh stays runnable as
# :rotate-buildbuddy-key-sh and is held to the port by the parity test below.

# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

exports_files(["rotate.sh"])

rust_library(
    name = "rotate_buildbuddy_key_lib",
    srcs = ["src/lib.rs"],
    crate_name = "rotate_buildbuddy_key",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_binary(
    name = "rotate-buildbuddy-key",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":rotate_buildbuddy_key_lib"],
)

[
    alias(
        name = name,
        actual = ":rotate-buildbuddy-key",
        visibility = ["//visibility:public"],
    )
    for name in [
        "rotate-buildbuddy-key-rs",
        "rotate-buildbuddy-key_rs",
    ]
]

# The shell original, kept runnable.
sh_binary(
    name = "rotate-buildbuddy-key-sh",
    srcs = ["rotate.sh"],
    visibility = ["//visibility:public"],
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "rotate_buildbuddy_key_lib_test",
    size = "small",
    crate = ":rotate_buildbuddy_key_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Script and binary side by side on every case in
# rotate_buildbuddy_key_rs_parity_test.py: exit code, stdout, stderr, and the
# gh / open / sleep calls (argv, and the key each `gh secret set` got on
# stdin), compared byte for byte. It also checks that the key never reaches
# the output or any argv.
py_test(
    name = "rotate_buildbuddy_key_rs_parity_test",
    size = "medium",
    srcs = ["rotate_buildbuddy_key_rs_parity_test.py"],
    data = [
        "rotate.sh",
        ":rotate-buildbuddy-key",
    ],
    env = {
        "ROTATE_RS": "$(rootpath :rotate-buildbuddy-key)",
        "ROTATE_SH": "$(rootpath rotate.sh)",
    },
    main = "rotate_buildbuddy_key_rs_parity_test.py",
    deps = ["//tools/shell-compat:parity_harness"],
)
