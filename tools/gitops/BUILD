"""GitOps `bazel run` wrappers — kubectl behind bazel (see defs.bzl).

Generic passthroughs forward manifests via `-- -f <path>`:
    bazel run //tools/gitops:apply -- -f gitops/argocd/root-projects.yaml
    bazel run //tools/gitops:status
Per-component declared targets come from the gitops_manifest macro.
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

exports_files(["gitops_cmd.sh"])

sh_binary(
    name = "apply",
    srcs = ["gitops_cmd.sh"],
    args = ["apply"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "delete",
    srcs = ["gitops_cmd.sh"],
    args = ["delete"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "diff",
    srcs = ["gitops_cmd.sh"],
    args = ["diff"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "get",
    srcs = ["gitops_cmd.sh"],
    args = ["get"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "patch",
    srcs = ["gitops_cmd.sh"],
    args = ["patch"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "status",
    srcs = ["gitops_cmd.sh"],
    args = ["status"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "helm",
    srcs = ["gitops_cmd.sh"],
    args = ["helm"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "kubeseal",
    srcs = ["gitops_cmd.sh"],
    args = ["kubeseal"],
    visibility = ["//visibility:public"],
)

# One-step operational task: seal the ntfy alert-delivery endpoint that
# Alertmanager reads (SealedSecret alertmanager-ntfy-endpoint/ntfy-url in
# `monitoring`). Wraps the create-secret | kubeseal chain behind one arg.
#   bazel run //tools/gitops:seal-alert-ntfy -- 'https://ntfy.host/mytopic'
sh_binary(
    name = "seal-alert-ntfy",
    srcs = ["seal_alert_ntfy.sh"],
    visibility = ["//visibility:public"],
)

# Mint AND seal the read-only ArgoCD token the Backstage ArgoCD cards use. Unlike
# seal-alert-ntfy this creates the credential itself, so it never passes through
# a clipboard. Requires the `backstage` role on platform-project to be merged and
# synced first (the script says so explicitly if it is not).
#   bazel run //tools/gitops:seal-argocd-backstage-token
#   bazel run //tools/gitops:seal-argocd-backstage-token -- --apply
sh_binary(
    name = "seal-argocd-backstage-token",
    srcs = ["seal_argocd_backstage_token.sh"],
    visibility = ["//visibility:public"],
)

# Back up / restore the sealed-secrets controller private keys to/from Bitwarden.
# Unlock is automatic (prompts for the master password if locked); `bw login` once first.
sh_binary(
    name = "sealed-secrets-backup",
    srcs = ["sealed_secrets_keys.sh"],
    args = ["backup"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "sealed-secrets-restore",
    srcs = ["sealed_secrets_keys.sh"],
    args = ["restore"],
    visibility = ["//visibility:public"],
)

# Read-only: confirm the key attachment exists in Bitwarden and decodes to >=1 Secret.
sh_binary(
    name = "sealed-secrets-verify",
    srcs = ["sealed_secrets_keys.sh"],
    args = ["verify"],
    visibility = ["//visibility:public"],
)

# Back up / restore / verify the ArgoCD argocd-secret (server.secretkey + mcp token
# seed) to/from Bitwarden. ArgoCD is the pulumi bootstrap, so its secret can't be a
# SealedSecret; this keeps the signing key + token seed restorable across reinstalls.
sh_binary(
    name = "argocd-secret-backup",
    srcs = ["argocd_secret.sh"],
    args = ["backup"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "argocd-secret-restore",
    srcs = ["argocd_secret.sh"],
    args = ["restore"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "argocd-secret-verify",
    srcs = ["argocd_secret.sh"],
    args = ["verify"],
    visibility = ["//visibility:public"],
)

# One-time bootstrap for the self-hosted ntfy instance (gitops/argocd/platform/ntfy):
# creates the alertmanager (write-only) and james (read-only) ntfy users that
# auth-default-access: deny-all requires before anything can publish/subscribe.
#   bazel run //tools/gitops:ntfy-bootstrap-users -- vitruvian-alerts
sh_binary(
    name = "ntfy-bootstrap-users",
    srcs = ["ntfy_bootstrap_users.sh"],
    visibility = ["//visibility:public"],
)

# General-purpose ntfy account lifecycle management (list/add/delete users,
# rotate passwords, change roles, grant/revoke per-topic access) — generalizes
# ntfy-bootstrap-users above to any account, not just the initial two.
#   bazel run //tools/gitops:ntfy-user-list
#   bazel run //tools/gitops:ntfy-user-add -- USERNAME [admin|user]
#   bazel run //tools/gitops:ntfy-user-del -- USERNAME
#   bazel run //tools/gitops:ntfy-user-change-pass -- USERNAME
#   bazel run //tools/gitops:ntfy-user-change-role -- USERNAME admin|user
#   bazel run //tools/gitops:ntfy-user-access -- USERNAME TOPIC PERMISSION
sh_binary(
    name = "ntfy-user-list",
    srcs = ["ntfy_manage_users.sh"],
    args = ["list"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "ntfy-user-add",
    srcs = ["ntfy_manage_users.sh"],
    args = ["add"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "ntfy-user-del",
    srcs = ["ntfy_manage_users.sh"],
    args = ["del"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "ntfy-user-change-pass",
    srcs = ["ntfy_manage_users.sh"],
    args = ["change-pass"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "ntfy-user-change-role",
    srcs = ["ntfy_manage_users.sh"],
    args = ["change-role"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "ntfy-user-access",
    srcs = ["ntfy_manage_users.sh"],
    args = ["access"],
    visibility = ["//visibility:public"],
)
