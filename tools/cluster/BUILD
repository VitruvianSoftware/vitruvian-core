"""Cluster/node lifecycle `bazel run` wrappers — kubectl behind bazel (see
cluster_cmd.sh). Complements //tools/gitops (ArgoCD-manifest oriented) with the
live-cluster node operations it doesn't cover:

    bazel run //tools/cluster:kubectl     -- get nodes -o wide
    bazel run //tools/cluster:cordon      -- nuc9
    bazel run //tools/cluster:drain       -- nuc9 --timeout=5m
    bazel run //tools/cluster:delete-node -- nuc9
    bazel run //tools/cluster:label-node  -- nuc9i5 node.ipv1337.dev/link=wired --overwrite

`:kubectl` is a general passthrough for anything the named ops don't cover
(wait, exec, delete pod/pvc, patch, ...).
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

exports_files(["cluster_cmd.sh"])

[
    sh_binary(
        name = op,
        srcs = ["cluster_cmd.sh"],
        args = [op],
        visibility = ["//visibility:public"],
    )
    for op in [
        "kubectl",
        "cordon",
        "uncordon",
        "drain",
        "delete-node",
        "label-node",
    ]
]
