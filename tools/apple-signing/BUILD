"""The Developer ID certificate and notary API key that sign the Vitruvian app.

  bazel run //tools/apple-signing -- csr
  bazel run //tools/apple-signing -- secrets <KEY_ID> <ISSUER_ID> <AuthKey_*.p8>
  bazel run //tools/apple-signing -- check
  bazel run //tools/apple-signing -- notary-status [SUBMISSION_ID]

Asking Apple for the certificate and creating the API key are the two steps
that cannot live here: Apple has no API for them and both need the account
holder signed in. See README.md.

`:apple-signing` is the Rust port (src/): apple-signing.sh's subcommands,
calls, files, output and exit codes, with its python3 JSON done through serde.
The script stays runnable as `:apple-signing-sh` and is held to the port by
the parity test below.
"""

# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["apple-signing.sh"])

rust_library(
    name = "apple_signing_lib",
    srcs = ["src/lib.rs"],
    crate_name = "apple_signing",
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
    name = "apple-signing",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":apple_signing_lib"],
)

alias(
    name = "apple-signing-rs",
    actual = ":apple-signing",
    visibility = ["//visibility:public"],
)

alias(
    name = "apple_signing_rs",
    actual = ":apple-signing",
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "apple-signing-sh",
    srcs = ["apple-signing.sh"],
    visibility = ["//visibility:public"],
)

# Offline: gh, bw, xcrun and security are fakes; the certificate is a throwaway.
sh_test(
    name = "apple-signing_test",
    size = "small",
    srcs = ["apple-signing_test.sh"],
    data = ["apple-signing.sh"],
)

# The same suite against the Rust binary (APPLE_SIGNING_BIN).
sh_test(
    name = "apple-signing-rs_test",
    size = "small",
    srcs = ["apple-signing_test.sh"],
    data = [
        "apple-signing.sh",
        ":apple-signing",
    ],
    env = {"APPLE_SIGNING_BIN": "$(rootpath :apple-signing)"},
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "apple_signing_lib_test",
    size = "small",
    crate = ":apple_signing_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Script and binary side by side on every case in
# apple_signing_rs_parity_test.py: exit code, stdout, stderr, the calls made
# to fake gh, bw, xcrun, security and curl (with what they were sent), and
# every file left in the signing folder.
py_test(
    name = "apple_signing_rs_parity_test",
    size = "medium",
    srcs = ["apple_signing_rs_parity_test.py"],
    data = [
        "apple-signing.sh",
        ":apple-signing",
    ],
    env = {
        "APPLE_SIGNING_RS": "$(rootpath :apple-signing)",
        "APPLE_SIGNING_SH": "$(rootpath apple-signing.sh)",
    },
    main = "apple_signing_rs_parity_test.py",
    deps = ["//tools/shell-compat:parity_harness"],
)
