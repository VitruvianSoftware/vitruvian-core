# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""Cluster/node lifecycle `bazel run` wrappers — kubectl behind bazel (see
cluster_cmd.sh). Complements //tools/gitops (ArgoCD-manifest oriented) with the
live-cluster node operations it doesn't cover:

    bazel run //tools/cluster:kubectl      -- get nodes -o wide
    bazel run //tools/cluster:cordon       -- nuc9
    bazel run //tools/cluster:drain        -- nuc9 --timeout=5m
    bazel run //tools/cluster:delete-node  -- nuc9
    bazel run //tools/cluster:label-node   -- nuc9i5 node.ipv1337.dev/link=wired --overwrite

Read-only HA / node-balance diagnostics (the audits behind the cluster-balance
and replica-spread reviews):

    bazel run //tools/cluster:balance                 # pods-per-node distribution
    bazel run //tools/cluster:placement    -- -n monitoring -l app.kubernetes.io/name=alertmanager
    bazel run //tools/cluster:minio-status            # drive/heal health + PV-node pinning

`:kubectl` is a general passthrough for anything the named ops don't cover
(wait, exec, delete pod/pvc, patch, ...).

`:<op>` is the Rust port (src/), with the op baked in as its first argument
exactly as cluster_cmd.sh had it; the script stays as `:<op>-sh`. Nothing
here reads or writes JSON, so the crate takes std only.
"""

# Hand-written: gazelle would generate targets for the parity test.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["cluster_cmd.sh"])

_OPS = [
    "kubectl",
    "cordon",
    "uncordon",
    "drain",
    "delete-node",
    "label-node",
    "balance",
    "placement",
    "minio-status",
]

rust_library(
    name = "cluster_lib",
    srcs = ["src/lib.rs"],
    crate_name = "cluster",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

[
    rust_binary(
        name = op,
        srcs = ["src/main.rs"],
        args = [op],
        edition = "2021",
        rustc_flags = ["-Copt-level=3"],
        visibility = ["//visibility:public"],
        deps = [":cluster_lib"],
    )
    for op in _OPS
]

[
    sh_binary(
        name = op + "-sh",
        srcs = ["cluster_cmd.sh"],
        args = [op],
        visibility = ["//visibility:public"],
    )
    for op in _OPS
]

[
    alias(
        name = op + "-rs",
        actual = ":" + op,
        visibility = ["//visibility:public"],
    )
    for op in _OPS
]

[
    alias(
        name = op.replace("-", "_") + "_rs",
        actual = ":" + op,
        visibility = ["//visibility:public"],
    )
    for op in _OPS
]

rust_test(
    name = "cluster_lib_test",
    size = "small",
    crate = ":cluster_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# One contract, both implementations, with a stand-in kubectl. The binary is
# any op's: the test passes the op itself, as the baked-in args would.
sh_test(
    name = "cluster_test",
    size = "small",
    srcs = ["cluster_test.sh"],
    args = ["$(location cluster_cmd.sh)"],
    data = ["cluster_cmd.sh"],
)

sh_test(
    name = "cluster-rs_test",
    size = "small",
    srcs = ["cluster_test.sh"],
    args = ["$(location :kubectl)"],
    data = [":kubectl"],
)

# cluster_cmd.sh and the binary side by side: exit status, stdout, stderr and
# every kubectl call (arguments, KUBECONFIG, working directory) must match.
py_test(
    name = "cluster_rs_parity_test",
    size = "medium",
    srcs = ["cluster_rs_parity_test.py"],
    data = [
        "cluster_cmd.sh",
        ":kubectl",
    ],
    env = {
        "CLUSTER_RS": "$(rootpath :kubectl)",
        "CLUSTER_SH": "$(rootpath cluster_cmd.sh)",
    },
    main = "cluster_rs_parity_test.py",
)
