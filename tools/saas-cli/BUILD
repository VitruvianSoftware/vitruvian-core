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

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["saas-cli.sh"])

SUBCOMMANDS = [
    "neon",
    "upstash",
    "whoami",
]

# The tool, in Rust (src/): saas-cli.sh's gcloud and npx calls, the
# credentials handed over in the environment, output and exit codes, held to
# the script by the parity test below. One library; each subcommand is the
# same src/main.rs with the subcommand baked in as $1.
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

# The shell original, kept runnable and held to the port by the parity test.
[
    sh_binary(
        name = sub + "-sh",
        srcs = ["saas-cli.sh"],
        args = [sub],
        visibility = ["//visibility:public"],
    )
    for sub in SUBCOMMANDS
]

# Hermetic guard for the properties that justify a wrapper over a README
# snippet: the credential reaches the CLI via the ENVIRONMENT and never argv
# (which `ps` exposes) or the output, the CLI version is pinned, every gcloud
# call is identity+project pinned, and both a gcloud auth failure (which exits
# 0!) and an unseeded secret are fatal with an actionable message.
sh_test(
    name = "saas-cli_test",
    srcs = ["saas-cli_test.sh"],
    data = [
        "saas-cli.sh",
        "//tools/pulumi:resolve_identity.sh",
    ],
)

# The same suite against the Rust binary (SAAS_CLI_BIN); its subcommand is
# passed as an argument, as the script's is.
sh_test(
    name = "saas-cli-rs_test",
    srcs = ["saas-cli_test.sh"],
    data = [
        "saas-cli.sh",
        ":whoami",
        "//tools/pulumi:resolve_identity.sh",
    ],
    env = {"SAAS_CLI_BIN": "$(rootpath :whoami)"},
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "saas_cli_lib_test",
    size = "small",
    crate = ":saas_cli_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Script and binary side by side on every case in saas_cli_rs_parity_test.py:
# exit code, stdout, stderr, the gcloud calls and the npx calls (argv and the
# credentials in their environment), compared byte for byte, with the real
# identity resolver.
py_test(
    name = "saas_cli_rs_parity_test",
    size = "medium",
    srcs = ["saas_cli_rs_parity_test.py"],
    data = [
        "saas-cli.sh",
        ":whoami",
        "//tools/pulumi:resolve_identity.sh",
    ],
    env = {
        "RESOLVE_IDENTITY": "$(rootpath //tools/pulumi:resolve_identity.sh)",
        "SAAS_CLI_RS": "$(rootpath :whoami)",
        "SAAS_CLI_SH": "$(rootpath saas-cli.sh)",
    },
    main = "saas_cli_rs_parity_test.py",
    deps = ["//tools/shell-compat:parity_harness"],
)

alias(
    name = "saas_cli_test",
    actual = ":saas-cli_test",
    deprecation = "Target :saas_cli_test is deprecated. Use :saas-cli_test instead. Will be removed in Phase 5.",
)
