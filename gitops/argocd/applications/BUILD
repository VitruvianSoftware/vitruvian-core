# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

# Lets tests read Application manifests. Argo CD's directory source here only
# loads .yaml/.yml/.json, so this file is invisible to it.
exports_files(
    ["cicd-telemetry.yaml"],
    visibility = ["//gitops/argocd/platform/cicd-telemetry:__pkg__"],
)
