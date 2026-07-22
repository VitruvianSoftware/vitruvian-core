"""saas-cli `bazel run` wrappers — the Neon and Upstash CLIs, pre-authenticated.

For TROUBLESHOOTING and read-mostly operational work. Provisioning belongs to
tabula/infra/data; creating or deleting a database through these CLIs puts it
outside Pulumi state and the next apply will fight you.

Authentication is not a step: both credentials live in the shared
infra-pipeline project's Secret Manager (seeded via //tools/gcp-secrets) and are
resolved per invocation, so nothing is cached on disk and what you see locally
is what CI sees. The GCP identity used to read them is pinned from
infrastructure/gcp-identities.tsv, never ambient gcloud (principles §2.2).

The calling sh_binary bakes the subcommand as $1 (mirrors //tools/sync-env-secrets
and //tools/gcp-secrets). Everything after `--` is forwarded to the CLI verbatim.

  bazel run //tools/saas-cli:whoami                        # verify both credentials work
  bazel run //tools/saas-cli:neon    -- projects list
  bazel run //tools/saas-cli:neon    -- connection-string <project-id>
  bazel run //tools/saas-cli:upstash -- redis list
  bazel run //tools/saas-cli:upstash -- redis get <id>
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["saas-cli.sh"])

sh_binary(
    name = "neon",
    srcs = ["saas-cli.sh"],
    args = ["neon"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "upstash",
    srcs = ["saas-cli.sh"],
    args = ["upstash"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "whoami",
    srcs = ["saas-cli.sh"],
    args = ["whoami"],
    visibility = ["//visibility:public"],
)

# Hermetic guard for the properties that justify a wrapper over a README
# snippet: the credential reaches the CLI via the ENVIRONMENT and never argv
# (which `ps` exposes) or the output, the CLI version is pinned, every gcloud
# call is identity+project pinned, and both a gcloud auth failure (which exits
# 0!) and an unseeded secret are fatal with an actionable message.
sh_test(
    name = "saas_cli_test",
    srcs = ["saas-cli_test.sh"],
    data = [
        "saas-cli.sh",
        "//tools/pulumi:resolve_identity.sh",
    ],
)
