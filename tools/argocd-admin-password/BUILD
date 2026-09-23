"""Pin the dev-local Argo CD admin password to a Bitwarden-held value.

See sync.sh for the why. Run from the main checkout (it needs the gitignored
Pulumi.local.yaml):

  bazel run //tools/sync-env-secrets:unlock        # once, if the vault is locked
  bazel run //tools/argocd-admin-password:sync
  bazel run //infrastructure/pulumi/platform/dev-local:preview   # then :up
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

sh_binary(
    name = "sync",
    srcs = ["sync.sh"],
)
