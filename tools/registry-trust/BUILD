# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Registry trust in code: which registry trusts which workflow, and proof
that a released version came from that workflow and not from a person."""

# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_library", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# The packages, their registries, mirrors and workflows, all read from
# release-please, the package files, copy.bara.sky and the mirrors' workflows.
py_library(
    name = "registry_trust",
    srcs = [
        "check.py",
        "inventory.py",
        "setup_publishers.py",
    ],
    imports = ["."],
)

py_binary(
    name = "inventory",
    srcs = ["inventory.py"],
    imports = ["."],
    main = "inventory.py",
    visibility = ["//visibility:public"],
)

# Asks npm, crates.io and PyPI, in public and with no token, whether every
# released version was published by the mirror's workflow. Needs the network,
# so it is a command and a scheduled workflow (registry-trust.yaml), not a test.
py_binary(
    name = "check",
    srcs = ["check.py"],
    imports = ["."],
    main = "check.py",
    visibility = ["//visibility:public"],
    deps = [":registry_trust"],
)

# Creates the crates.io trusted publisher that is missing, hands npm's to
# //tools/npm-trusted-publisher:setup, and prints what PyPI needs entered.
py_binary(
    name = "setup",
    srcs = ["setup_publishers.py"],
    imports = ["."],
    main = "setup_publishers.py",
    visibility = ["//visibility:public"],
    deps = [":registry_trust"],
)

py_library(
    name = "fixture_repo",
    testonly = True,
    srcs = ["fixture_repo.py"],
    imports = ["."],
)

py_test(
    name = "inventory_test",
    size = "small",
    srcs = ["inventory_test.py"],
    # The real file, so a change to its layout that hides a mirror fails here.
    data = ["//tools/copybara:copy.bara.sky"],
    main = "inventory_test.py",
    deps = [
        ":fixture_repo",
        ":registry_trust",
    ],
)

# Recorded registry answers; no test touches the network.
py_test(
    name = "check_test",
    size = "small",
    srcs = ["check_test.py"],
    data = ["bootstrap.tsv"] + glob(["testdata/*.json"]),
    main = "check_test.py",
    deps = [
        ":fixture_repo",
        ":registry_trust",
    ],
)

py_test(
    name = "setup_test",
    size = "small",
    srcs = ["setup_publishers_test.py"],
    main = "setup_publishers_test.py",
    deps = [
        ":fixture_repo",
        ":registry_trust",
    ],
)

# The same three commands in Rust, standard library only: one binary that
# runs as `inventory`, `check` or `setup`, by the name it is run as or by
# its first argument. Live HTTPS goes through curl (the cargo token on its
# stdin, never its command line).
rust_library(
    name = "registry_trust_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    # The unit tests read the recorded answers, the real ledger and the real
    # copy.bara.sky with include_str!.
    compile_data = [
        "bootstrap.tsv",
        "//tools/copybara:copy.bara.sky",
    ] + glob(["testdata/*.json"]),
    crate_name = "registry_trust",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "registry-trust-rs",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":registry_trust_lib"],
)

alias(
    name = "registry_trust_rs",
    actual = ":registry-trust-rs",
)

rust_test(
    name = "registry_trust_lib_test",
    size = "small",
    crate = ":registry_trust_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Holds the Rust binary to the scripts: every scenario of inventory_test.py,
# check_test.py and setup_publishers_test.py, and inputs built to break
# them, run through both with the same recorded registry answers, comparing
# exit codes, stdout, stderr and every request made.
py_test(
    name = "registry_trust_rs_parity_test",
    size = "small",
    srcs = ["registry_trust_rs_parity_test.py"],
    data = [
        "bootstrap.tsv",
        ":registry-trust-rs",
        "//tools/copybara:copy.bara.sky",
    ] + glob(["testdata/*.json"]),
    env = {"REGISTRY_TRUST_RS": "$(rootpath :registry-trust-rs)"},
    main = "registry_trust_rs_parity_test.py",
    deps = [
        ":fixture_repo",
        ":registry_trust",
    ],
)
