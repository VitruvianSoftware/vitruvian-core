# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("//tools/pytest:defs.bzl", "py_test")

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
