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

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["gcp-secrets.sh"])

# The tool, in Rust (src/): gcp-secrets.sh's calls, prompts, output and exit
# codes, held to the script by the parity test below. One library; each
# subcommand is the same src/main.rs with the subcommand baked in as $1.
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

[
    alias(
        name = name,
        actual = ":" + sub,
        visibility = ["//visibility:public"],
    )
    for sub in [
        "status",
        "seed",
    ]
    for name in [
        sub + "-rs",
        sub + "_rs",
    ]
]

# The shell original, kept runnable and held to the port by the parity test.
sh_binary(
    name = "status-sh",
    srcs = ["gcp-secrets.sh"],
    args = ["status"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "seed-sh",
    srcs = ["gcp-secrets.sh"],
    args = ["seed"],
    visibility = ["//visibility:public"],
)

# Hermetic guard for the safety properties that justify this tool existing at
# all: the value goes in on stdin (never argv, which `ps` exposes), never
# reaches stdout/stderr, every call is identity+project pinned, and a re-run
# cannot silently stack a second version. Runs under `bazel test //...`, so it
# cannot become a test that is written but never executed.
sh_test(
    name = "gcp-secrets_test",
    srcs = ["gcp-secrets_test.sh"],
    data = [
        "gcp-secrets.sh",
        "//tools/pulumi:resolve_identity.sh",
    ],
)

# The same suite against the Rust binary (GCP_SECRETS_BIN); its subcommand
# is passed as an argument, as the script's is.
sh_test(
    name = "gcp-secrets-rs_test",
    srcs = ["gcp-secrets_test.sh"],
    data = [
        "gcp-secrets.sh",
        ":status",
        "//tools/pulumi:resolve_identity.sh",
    ],
    env = {"GCP_SECRETS_BIN": "$(rootpath :status)"},
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "gcp_secrets_lib_test",
    size = "small",
    crate = ":gcp_secrets_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Script and binary side by side on every case in gcp_secrets_rs_parity_test.py:
# exit code, stdout, stderr and the gcloud calls (argv and stdin), compared
# byte for byte, with the real identity resolver.
py_test(
    name = "gcp_secrets_rs_parity_test",
    size = "medium",
    srcs = ["gcp_secrets_rs_parity_test.py"],
    data = [
        "gcp-secrets.sh",
        ":status",
        "//tools/pulumi:resolve_identity.sh",
    ],
    env = {
        "GCP_SECRETS_RS": "$(rootpath :status)",
        "GCP_SECRETS_SH": "$(rootpath gcp-secrets.sh)",
        "RESOLVE_IDENTITY": "$(rootpath //tools/pulumi:resolve_identity.sh)",
    },
    main = "gcp_secrets_rs_parity_test.py",
    deps = ["//tools/shell-compat:parity_harness"],
)

alias(
    name = "gcp_secrets_test",
    actual = ":gcp-secrets_test",
    deprecation = "Target :gcp_secrets_test is deprecated. Use :gcp-secrets_test instead. Will be removed in Phase 5.",
)
