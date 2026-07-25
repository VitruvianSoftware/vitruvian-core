"""gcp-secrets `bazel run` wrappers — seed/inspect GCP Secret Manager secret
VALUES, the one part of a secret that cannot ship as code.

The secret's CONTAINER and IAM are declared in Pulumi and applied by the
pipeline; the VALUE cannot be committed (even Pulumi-encrypted) without putting
a secret in git history forever, so it is piped in here once by a human holding
it. Sibling of //tools/sync-env-secrets, which covers the GitHub Actions secret
class and deliberately does NOT cover GCP Secret Manager.

The calling sh_binary bakes the subcommand as $1 (mirrors //tools/sync-env-secrets
and //tools/gitops). Identity and target project come from
infrastructure/gcp-identities.tsv keyed on the app's infra dir — never ambient
gcloud (principles §2.2).

  bazel run //tools/gcp-secrets:status -- tabula/infra/build          # which secrets still need a value
  bazel run //tools/gcp-secrets:seed   -- tabula/infra/build          # fill in every unseeded one
  bazel run //tools/gcp-secrets:seed   -- tabula/infra/build NEON_API_KEY
  bazel run //tools/gcp-secrets:seed   -- tabula/infra/build --force NEON_API_KEY   # rotate
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["gcp-secrets.sh"])

sh_binary(
    name = "status",
    srcs = ["gcp-secrets.sh"],
    args = ["status"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "seed",
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
    name = "gcp_secrets_test",
    srcs = ["gcp-secrets_test.sh"],
    data = [
        "gcp-secrets.sh",
        "//tools/pulumi:resolve_identity.sh",
    ],
)
