# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""saas-cli `bazel run` wrappers — the Neon and Upstash CLIs, pre-authenticated.

For TROUBLESHOOTING and read-mostly operational work. Provisioning belongs to
tabula/infra/data; creating or deleting a database through these CLIs puts it
outside Pulumi state and the next apply will fight you.

Authentication is not a step: both credentials live in the shared
infra-pipeline project's Secret Manager (seeded via //tools/gcp-secrets) and are
resolved per invocation, so nothing is cached on disk and what you see locally
is what CI sees. The GCP identity used to read them is pinned from
infrastructure/gcp-identities.tsv, never ambient gcloud (principles §2.2).

Each binary target bakes the subcommand as $1 (mirrors //tools/sync-env-secrets
and //tools/gcp-secrets). Everything after `--` is forwarded to the CLI verbatim.

  bazel run //tools/saas-cli:whoami                        # verify both credentials work
  bazel run //tools/saas-cli:neon    -- projects list
  bazel run //tools/saas-cli:neon    -- connection-string <project-id>
  bazel run //tools/saas-cli:upstash -- redis list
  bazel run //tools/saas-cli:upstash -- redis get <id>
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

SUBCOMMANDS = [
    "neon",
    "upstash",
    "whoami",
]

rust_library(
    name = "saas_cli_lib",
    srcs = ["src/lib.rs"],
    crate_name = "saas_cli",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

[
    rust_binary(
        name = sub,
        srcs = ["src/main.rs"],
        args = [sub],
        data = ["//tools/pulumi:resolve_identity.sh"],
        edition = "2021",
        rustc_flags = ["-Copt-level=3"],
        visibility = ["//visibility:public"],
        deps = [
            ":saas_cli_lib",
            "//tools/shell-compat:shell_compat",
        ],
    )
    for sub in SUBCOMMANDS
]

[
    alias(
        name = name,
        actual = ":" + sub,
        visibility = ["//visibility:public"],
    )
    for sub in SUBCOMMANDS
    for name in [
        sub + "-rs",
        sub + "_rs",
    ]
]

rust_test(
    name = "saas_cli_lib_test",
    size = "small",
    crate = ":saas_cli_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "saas-cli_test",
    tests = [":saas_cli_lib_test"],
)

test_suite(
    name = "saas-cli-rs_test",
    tests = [":saas_cli_lib_test"],
)

test_suite(
    name = "saas_cli_test",
    tests = [":saas_cli_lib_test"],
)

test_suite(
    name = "login_test",
    tests = [":saas_cli_lib_test"],
)
