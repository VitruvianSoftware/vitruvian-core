"""sync-env-secrets `bazel run` wrappers — deploy-time GitHub Actions secrets that
are NOT in GCP Secret Manager, synced from a gitignored, Bitwarden-backed store.

The calling sh_binary bakes the subcommand as $1 (mirrors //tools/gitops). See
sync-env-secrets.sh + README.md and docs/engineering/application-development-principles.md
(§2.2 ops run through bazel wrappers, §2.18 every change ships as code).

  bazel run //tools/sync-env-secrets:unlock                            # once: caches a bw session so the rest run headless
  bazel run //tools/sync-env-secrets:apply -- oauth-user-inspector-development
  bazel run //tools/sync-env-secrets:bw-push
  bazel run //tools/sync-env-secrets:lock                              # clear the cached session + lock the vault
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

exports_files(["sync-env-secrets.sh"])

sh_binary(
    name = "apply",
    srcs = ["sync-env-secrets.sh"],
    args = ["apply"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "bw-push",
    srcs = ["sync-env-secrets.sh"],
    args = ["bw-push"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "bw-pull",
    srcs = ["sync-env-secrets.sh"],
    args = ["bw-pull"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "unlock",
    srcs = ["sync-env-secrets.sh"],
    args = ["unlock"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "lock",
    srcs = ["sync-env-secrets.sh"],
    args = ["lock"],
    visibility = ["//visibility:public"],
)
