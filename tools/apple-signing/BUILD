"""The Developer ID certificate and notary API key that sign the Vitruvian app.

  bazel run //tools/apple-signing -- csr
  bazel run //tools/apple-signing -- secrets <KEY_ID> <ISSUER_ID> <AuthKey_*.p8>
  bazel run //tools/apple-signing -- check
  bazel run //tools/apple-signing -- notary-status [SUBMISSION_ID]

Asking Apple for the certificate and creating the API key are the two steps
that cannot live here: Apple has no API for them and both need the account
holder signed in. See README.md.

`:apple-signing` is the Rust implementation (src/).
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

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

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "apple_signing_lib_test",
    size = "small",
    crate = ":apple_signing_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "setup_test",
    tests = [":apple_signing_lib_test"],
)

test_suite(
    name = "apple-signing_test",
    tests = [":apple_signing_lib_test"],
)

test_suite(
    name = "apple_signing_test",
    tests = [":apple_signing_lib_test"],
)
