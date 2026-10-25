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

# Break-glass local release publisher: the PUBLISH half (npm publish + Go-module
# tags) of a mirror release, for when GitHub Actions is down. The EXPORT half is
# //tools/copybara/sync. GoReleaser binaries + nexus-agent stay manual (runbook).
#
# :publish-local is the Rust port (src/); publish-local.sh stays runnable as
# :publish-local-sh and is held to the port by the parity test below.

# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["publish-local.sh"])

# publish-local.sh's logic: the slash-form Go tag, the manifests and
# package.json read natively (serde_json, with the script's `jq -r`
# semantics), and the same git / gh / npm calls.
rust_library(
    name = "release_lib",
    srcs = ["src/lib.rs"],
    crate_name = "publish_local",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "publish-local",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":release_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[
    alias(
        name = name,
        actual = ":publish-local",
        visibility = ["//visibility:public"],
    )
    for name in [
        "publish-local-rs",
        "publish-local_rs",
    ]
]

# The shell original, kept runnable.
sh_binary(
    name = "publish-local-sh",
    srcs = ["publish-local.sh"],
    visibility = ["//visibility:public"],
)

# Regression guard for the slash-form Go-module tag (the cloud_run "unknown
# revision" bug). Runs under `bazel test //...`.
sh_test(
    name = "publish-local_test",
    srcs = ["publish-local_test.sh"],
    args = ["$(location publish-local.sh)"],
    data = ["publish-local.sh"],
)

# The same guard against the Rust binary (PUBLISH_LOCAL_BIN).
sh_test(
    name = "publish-local-rs_test",
    srcs = ["publish-local_test.sh"],
    args = ["$(location publish-local.sh)"],
    data = [
        "publish-local.sh",
        ":publish-local",
    ],
    env = {"PUBLISH_LOCAL_BIN": "$(rootpath :publish-local)"},
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "release_lib_test",
    size = "small",
    crate = ":release_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Script and binary side by side on every case in
# publish_local_rs_parity_test.py: exit code, stdout, stderr, and the git /
# gh / npm calls (argv, cwd, the npm token in the environment), compared byte
# for byte.
py_test(
    name = "publish_local_rs_parity_test",
    size = "medium",
    srcs = ["publish_local_rs_parity_test.py"],
    data = [
        "publish-local.sh",
        ":publish-local",
    ],
    env = {
        "PUBLISH_LOCAL_RS": "$(rootpath :publish-local)",
        "PUBLISH_LOCAL_SH": "$(rootpath publish-local.sh)",
    },
    main = "publish_local_rs_parity_test.py",
    deps = ["//tools/shell-compat:parity_harness"],
)
