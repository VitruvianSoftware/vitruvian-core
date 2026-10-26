# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

# Hand-written: gazelle has no Rust extension here, and the shell fallbacks and
# parity tests below are not something it would generate.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files([
    "bootstrap.sh",
    "setup.sh",
])

# src/ is setup.sh and bootstrap.sh in Rust: same discovery, same npm calls,
# same output and exit codes, byte for byte (see :npm_trusted_publisher_rs_parity_test).
# It reads package.json with serde_json the way the scripts' python3 snippets
# read it. src/lib.rs lists the few places it cannot match bash to the byte.
rust_library(
    name = "npm_trusted_publisher_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/bin/*.rs"],
    ),
    # bootstrap --help prints bootstrap.sh's own Usage block; a unit test holds
    # the default two-factor wait to setup.sh's.
    compile_data = [
        "bootstrap.sh",
        "setup.sh",
    ],
    crate_name = "npm_trusted_publisher",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

# Configures npm trusted publishing for every publishable package in one pass.
# The npm UI re-challenges 2FA on page NAVIGATION, so doing this by hand costs
# ~62 hardware key touches; `npm trust` needs one.
rust_binary(
    name = "setup",
    srcs = ["src/bin/setup.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":npm_trusted_publisher_lib"],
)

# Gives a never-published package its FIRST publish, then hands off to setup.
# Trusted publishing attaches to a package that EXISTS, and the release workflow
# authenticates by OIDC alone -- so a brand-new name cannot be created by CI at
# all. Exactly one manual publish per package breaks that cycle. The hand-off
# runs `bash $SETUP_SH` when that names a file, else the Rust setup in-process.
rust_binary(
    name = "bootstrap",
    srcs = ["src/bin/bootstrap.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":npm_trusted_publisher_lib"],
)

alias(
    name = "setup-rs",
    actual = ":setup",
    visibility = ["//visibility:public"],
)

alias(
    name = "bootstrap-rs",
    actual = ":bootstrap",
    visibility = ["//visibility:public"],
)

# The original scripts, kept runnable as a fallback and as the parity oracle.
sh_binary(
    name = "setup-sh",
    srcs = ["setup.sh"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "bootstrap-sh",
    srcs = ["bootstrap.sh"],
    data = ["setup.sh"],
    visibility = ["//visibility:public"],
)

rust_test(
    name = "npm_trusted_publisher_lib_test",
    size = "small",
    crate = ":npm_trusted_publisher_lib",
    edition = "2021",
)

sh_test(
    name = "setup_test",
    size = "small",
    srcs = ["setup_test.sh"],
    args = ["$(location setup.sh)"],
    data = ["setup.sh"],
)

sh_test(
    name = "bootstrap_test",
    size = "small",
    srcs = ["bootstrap_test.sh"],
    args = ["$(location bootstrap.sh)"],
    data = ["bootstrap.sh"],
)

# The test scripts run their target with `bash`, so hand each a short script
# that execs the Rust binary beside it in the runfiles tree. setup_test.sh also
# reads the default two-factor wait out of its target, so the setup shim states
# the Rust binary's default, taken from src/setup.rs at build time.
genrule(
    name = "setup_rs_shim",
    srcs = ["src/setup.rs"],
    outs = ["setup_rs_shim.sh"],
    cmd = "wait=$$(sed -n 's/^pub const DEFAULT_OTP_WAIT_SECONDS: &str = \"\\([0-9]*\\)\";$$/\\1/p' $<); " +
          "test -n \"$$wait\" && " +
          "printf '%s\\n' '#!/usr/bin/env bash' " +
          "'# The Rust setup'\"'\"'s default two-factor wait (src/setup.rs), for setup_test.sh:' " +
          "\"OTP_WAIT_SECONDS=\\\"\\$${OTP_WAIT_SECONDS:-$$wait}\\\"\" " +
          "'exec \"$$(cd \"$$(dirname \"$${BASH_SOURCE[0]}\")\" && pwd)/setup\" \"$$@\"' > $@",
)

genrule(
    name = "bootstrap_rs_shim",
    outs = ["bootstrap_rs_shim.sh"],
    cmd = "printf '%s\\n' '#!/usr/bin/env bash' " +
          "'exec \"$$(cd \"$$(dirname \"$${BASH_SOURCE[0]}\")\" && pwd)/bootstrap\" \"$$@\"' > $@",
)

# The same suites, against the Rust binaries.
sh_test(
    name = "setup-rs_test",
    size = "small",
    srcs = ["setup_test.sh"],
    args = ["$(location :setup_rs_shim)"],
    data = [
        ":setup",
        ":setup_rs_shim",
    ],
)

sh_test(
    name = "bootstrap-rs_test",
    size = "small",
    srcs = ["bootstrap_test.sh"],
    args = ["$(location :bootstrap_rs_shim)"],
    data = [
        ":bootstrap",
        ":bootstrap_rs_shim",
    ],
)

# setup.sh / bootstrap.sh and the Rust binaries side by side over every
# scenario in the two shell suites plus the edge cases (odd JSON types and
# Python's str() of them, malformed NPM_TP_PACKAGES rows, the two-factor flows
# on a stand-in terminal, npm capability probing, workflow-name regexes, the
# hand-off to setup): stdout, stderr, exit code, every npm/git call and the
# files left behind must all be identical.
py_test(
    name = "npm_trusted_publisher_rs_parity_test",
    size = "medium",
    srcs = ["npm_trusted_publisher_rs_parity_test.py"],
    data = [
        "bootstrap.sh",
        "setup.sh",
        ":bootstrap",
        ":setup",
    ],
    env = {
        "NTP_BOOTSTRAP_RS": "$(rootpath :bootstrap)",
        "NTP_BOOTSTRAP_SH": "$(rootpath bootstrap.sh)",
        "NTP_SETUP_RS": "$(rootpath :setup)",
        "NTP_SETUP_SH": "$(rootpath setup.sh)",
    },
    main = "npm_trusted_publisher_rs_parity_test.py",
)
