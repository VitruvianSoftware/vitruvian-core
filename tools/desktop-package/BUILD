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

"""Reusable release packaging and distribution tooling for macOS desktop applications.

`:package-desktop` is the Rust port (src/); package-desktop.sh stays as
`:package-desktop-sh`, and as the file workflows and apps/desktop/home-speaker
run directly. Both are held to package-desktop_test.sh, and the parity test
runs them side by side.
"""

# Hand-written: gazelle would generate targets for the parity test.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files([
    "package-desktop.sh",
    "package-desktop_test.sh",
])

sh_binary(
    name = "package-desktop-sh",
    srcs = ["package-desktop.sh"],
    visibility = ["//visibility:public"],
)

# The Rust port. The script parses no JSON (gh's --jq does the filtering), so
# the crate takes std only. Optimised in every build mode.
rust_library(
    name = "package_desktop_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = [
            "src/main.rs",
            "src/probe.rs",
        ],
    ),
    crate_name = "package_desktop",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "package-desktop",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":package_desktop_lib"],
)

alias(
    name = "package_desktop",
    actual = ":package-desktop",
    visibility = ["//visibility:public"],
)

alias(
    name = "package-desktop-rs",
    actual = ":package-desktop",
    visibility = ["//visibility:public"],
)

alias(
    name = "package_desktop_rs",
    actual = ":package-desktop",
    visibility = ["//visibility:public"],
)

# Test-only: calls the port's helpers one at a time, so the shell test and
# the parity test can hold each to the shell function of the same name.
rust_binary(
    name = "package-desktop-rs-probe",
    testonly = True,
    srcs = ["src/probe.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":package_desktop_lib"],
)

rust_test(
    name = "package_desktop_lib_test",
    size = "small",
    crate = ":package_desktop_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

sh_test(
    name = "package-desktop_test",
    size = "small",
    srcs = ["package-desktop_test.sh"],
    data = [
        "package-desktop.sh",
    ],
)

# The same cases against the Rust binary: the helpers through the probe, the
# driver run directly in place of `bash package-desktop.sh`.
sh_test(
    name = "package-desktop-rs_test",
    size = "small",
    srcs = ["package-desktop_test.sh"],
    args = [
        "$(location :package-desktop)",
        "$(location :package-desktop-rs-probe)",
    ],
    data = [
        ":package-desktop",
        ":package-desktop-rs-probe",
    ],
)

# package-desktop.sh and :package-desktop side by side, with stand-ins for
# codesign, security, hdiutil, lipo, xcrun, gh, git, python3 and file that
# record every call: exit status, stdout, stderr, those records and the files
# left in dist must match in every mode and failure.
py_test(
    name = "package_desktop_rs_parity_test",
    size = "medium",
    srcs = ["package_desktop_rs_parity_test.py"],
    data = [
        "package-desktop.sh",
        ":package-desktop",
        ":package-desktop-rs-probe",
    ],
    env = {
        "PACKAGE_DESKTOP_PROBE": "$(rootpath :package-desktop-rs-probe)",
        "PACKAGE_DESKTOP_RS": "$(rootpath :package-desktop)",
        "PACKAGE_DESKTOP_SH": "$(rootpath package-desktop.sh)",
    },
    main = "package_desktop_rs_parity_test.py",
)
