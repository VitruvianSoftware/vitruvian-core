"""Pin the dev-local Argo CD admin password to a Bitwarden-held value.

See sync.sh for the why. Run from the main checkout (it needs the gitignored
Pulumi.local.yaml):

  bazel run //tools/sync-env-secrets:unlock        # once, if the vault is locked
  bazel run //tools/argocd-admin-password:sync
  bazel run //infrastructure/pulumi/platform/dev-local:preview   # then :up

`:sync` is the Rust implementation (src/).
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "argocd_admin_password_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "argocd_admin_password",
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
    name = "sync",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":argocd_admin_password_lib"],
)

alias(
    name = "sync-rs",
    actual = ":sync",
)

alias(
    name = "sync_rs",
    actual = ":sync",
)

# The #[cfg(test)] unit tests in src/ (the jq programs, base64, the item
# document, dates).
rust_test(
    name = "argocd_admin_password_lib_test",
    size = "small",
    crate = ":argocd_admin_password_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "sync_test",
    tests = [":argocd_admin_password_lib_test"],
)
