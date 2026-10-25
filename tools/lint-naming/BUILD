# Monorepo Naming Convention Linter & Test Harness.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

sh_binary(
    name = "lint-naming-py",
    srcs = ["lint_naming.py"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "lint-naming_test",
    size = "small",
    srcs = ["test_runner.sh"],
    data = glob([
        "*.py",
        "rules/*.py",
        "tests/*.py",
        "testdata/**/*",
    ]),
    visibility = ["//visibility:public"],
)

# --- Rust port ---------------------------------------------------------------
# src/ is lint_naming.py in Rust: same scan, rules, flags, help text, report,
# warnings and exit codes, byte for byte. It takes only std, no crate, so
# Cargo.lock and MODULE.bazel stay as they are. BUILD files are read the way
# the Python reads them, with ast.parse, so src/pyast carries a Python 3.12
# tokenizer and parser; src/unicode_tables.rs (from gen_unicode_tables.py)
# carries the character classes Python's str and re use. Optimised in every
# build mode.
rust_library(
    name = "lint_naming_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = [
            "src/main.rs",
            "src/probe.rs",
        ],
    ),
    crate_name = "lint_naming",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "lint-naming",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":lint_naming_lib"],
)

alias(
    name = "lint-naming-rs",
    actual = ":lint-naming",
    visibility = ["//visibility:public"],
)

alias(
    name = "lint_naming_rs",
    actual = ":lint-naming",
    visibility = ["//visibility:public"],
)

# Test-only: calls the port's rule functions one at a time, so the parity
# test can hold each to the Python function the test suites call.
rust_binary(
    name = "lint-naming-rs-probe",
    testonly = True,
    srcs = ["src/probe.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":lint_naming_lib"],
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "lint_naming_lib_test",
    size = "small",
    crate = ":lint_naming_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# lint_naming.py and lint-naming-rs side by side: every call the four test
# tiers make (replayed through the probe, and every scan and command line
# through both programs), testdata/, generated trees and command lines built
# to break them, and this repository's own tree. Exit codes, stdout and
# stderr must match byte for byte.
py_test(
    name = "lint_naming_rs_parity_test",
    size = "small",
    srcs = ["lint_naming_rs_parity_test.py"],
    data = glob([
        "*.py",
        "rules/*.py",
        "tests/*.py",
        "testdata/**/*",
    ]) + [
        "BUILD",
        "src/unicode_tables.rs",
        ":lint-naming",
        ":lint-naming-rs-probe",
    ],
    env = {
        "LINT_NAMING_RS": "$(rootpath :lint-naming)",
        "LINT_NAMING_RS_PROBE": "$(rootpath :lint-naming-rs-probe)",
    },
    main = "lint_naming_rs_parity_test.py",
)
