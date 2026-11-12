# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("//tools/gitops:defs.bzl", "gitops_manifest")

# :apply starts the drill, :delete removes it (cluster, PVC and verify job).
# See README.md for the full procedure.
gitops_manifest(
    name = "cnpg-restore-zitadel",
    manifests = [
        "cluster.yaml",
        "verify-job.yaml",
    ],
)
