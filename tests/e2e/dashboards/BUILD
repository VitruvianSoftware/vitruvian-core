# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

# gazelle:ignore

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

package(default_visibility = ["//visibility:public"])

_DATA = [
    ":tier1_schema_test.py",
    ":tier2_promql_test.py",
    ":tier3_integration_test.py",
    ":tier4_telemetry_test.py",
    "//gitops/argocd/platform/grafana-dashboards:grafana-dashboards-files",
]

sh_binary(
    name = "runner",
    srcs = ["runner.sh"],
    data = _DATA,
)

sh_test(
    name = "tier1_schema_test",
    size = "small",
    srcs = ["tier1_schema_test.py"],
    data = _DATA,
)

sh_test(
    name = "tier2_promql_test",
    size = "small",
    srcs = ["tier2_promql_test.py"],
    data = _DATA,
)

sh_test(
    name = "tier3_integration_test",
    size = "small",
    srcs = ["tier3_integration_test.py"],
    data = _DATA,
)

sh_test(
    name = "tier4_telemetry_test",
    size = "medium",
    srcs = ["tier4_telemetry_test.py"],
    data = _DATA,
    tags = ["manual"],
)

sh_test(
    name = "runner_test",
    size = "medium",
    srcs = ["runner.sh"],
    data = _DATA,
    tags = ["manual"],
)
