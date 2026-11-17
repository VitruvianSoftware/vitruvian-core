# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("//tools/pytest:defs.bzl", "py_test")

# Tests the server.py embedded in configmap.yaml (read from the ConfigMap
# itself, so the deployed code is what's tested).
py_test(
    name = "bridge_test",
    size = "small",
    srcs = ["bridge_test.py"],
    data = ["configmap.yaml"],
)

py_test(
    name = "exporter_test",
    size = "small",
    srcs = ["exporter_test.py"],
    data = [
        "deployment.yaml",
        "service.yaml",
        "//gitops/argocd/platform/grafana-dashboards:grafana-dashboards-files",
    ],
)
