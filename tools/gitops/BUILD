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
