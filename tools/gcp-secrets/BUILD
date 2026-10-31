"""gcp-secrets `bazel run` wrappers — seed/inspect GCP Secret Manager secret
VALUES, the one part of a secret that cannot ship as code.

The secret's CONTAINER and IAM are declared in Pulumi and applied by the
pipeline; the VALUE cannot be committed (even Pulumi-encrypted) without putting
a secret in git history forever, so it is piped in here once by a human holding
it. Sibling of //tools/sync-env-secrets, which covers the GitHub Actions secret
class and deliberately does NOT cover GCP Secret Manager.

Each binary target bakes the subcommand as $1 (mirrors //tools/sync-env-secrets
and //tools/gitops). Identity and target project come from
infrastructure/gcp-identities.tsv keyed on the app's infra dir — never ambient
gcloud (principles §2.2).

  bazel run //tools/gcp-secrets:status -- tabula/infra/build          # which secrets still need a value
  bazel run //tools/gcp-secrets:seed   -- tabula/infra/build          # fill in every unseeded one
  bazel run //tools/gcp-secrets:seed   -- tabula/infra/build NEON_API_KEY
  bazel run //tools/gcp-secrets:seed   -- tabula/infra/build --force NEON_API_KEY   # rotate
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# The tool, in Rust (src/): each subcommand is the same src/main.rs with the
# subcommand baked in as $1.
rust_library(
    name = "gcp_secrets_lib",
    srcs = ["src/lib.rs"],
    crate_name = "gcp_secrets",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_binary(
    name = "status",
    srcs = ["src/main.rs"],
    args = ["status"],
    data = ["//tools/pulumi:resolve_identity.sh"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":gcp_secrets_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "seed",
    srcs = ["src/main.rs"],
    args = ["seed"],
    data = ["//tools/pulumi:resolve_identity.sh"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":gcp_secrets_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "gcp_secrets_lib_test",
    size = "small",
    crate = ":gcp_secrets_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "sync_test",
    tests = [":gcp_secrets_lib_test"],
)

test_suite(
    name = "gcp-secrets_test",
    tests = [":gcp_secrets_lib_test"],
)

test_suite(
    name = "gcp_secrets_test",
    tests = [":gcp_secrets_lib_test"],
)
