# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

# Hand-written: gazelle has no Rust extension here, and the shell fallbacks and
# parity tests below are not something it would generate.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["check.sh"])

# Asks the REGISTRY whether our published packages are actually there, rather
# than asking the pipeline whether it thinks it published them. Those stopped
# being the same thing on 2026-05-07 and nothing noticed for three months.
#
# src/ is check.sh in Rust: same manifests, same checks, same output and exit
# codes, byte for byte (see :check_rs_parity_test). It reads package.json with
# serde_json the way the script's python3 snippets read it.
rust_library(
    name = "npm_publish_audit_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "npm_publish_audit",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "check",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":npm_publish_audit_lib"],
)

alias(
    name = "check-rs",
    actual = ":check",
    visibility = ["//visibility:public"],
)

# The original script, kept runnable as a fallback and as the parity oracle.
sh_binary(
    name = "check-sh",
    srcs = ["check.sh"],
    visibility = ["//visibility:public"],
)

rust_test(
    name = "npm_publish_audit_lib_test",
    size = "small",
    crate = ":npm_publish_audit_lib",
    edition = "2021",
)

sh_test(
    name = "check_test",
    size = "small",
    srcs = ["check_test.sh"],
    args = ["$(location check.sh)"],
    data = ["check.sh"],
)

# check_test.sh runs its target with `bash`, so hand it a one-line script that
# execs the Rust binary sitting beside it in the runfiles tree.
genrule(
    name = "check_rs_shim",
    outs = ["check_rs_shim.sh"],
    cmd = "printf '%s\\n' '#!/usr/bin/env bash' " +
          "'exec \"$$(cd \"$$(dirname \"$${BASH_SOURCE[0]}\")\" && pwd)/check\" \"$$@\"' > $@",
)

# The same suite, against the Rust binary.
sh_test(
    name = "check-rs_test",
    size = "small",
    srcs = ["check_test.sh"],
    args = ["$(location :check_rs_shim)"],
    data = [
        ":check",
        ":check_rs_shim",
    ],
)

# check.sh and the Rust binary side by side over every scenario in
# check_test.sh plus the edge cases (odd JSON types, Python's str() of them,
# symlinks, node_modules, npm misbehaving): stdout, stderr, exit code and the
# npm calls made must all be identical.
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
)
