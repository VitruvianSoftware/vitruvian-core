# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

package(default_visibility = ["//visibility:public"])

exports_files([
    "ci_pipelines_test.py",
    "runner.sh",
    "tier1_schema_test.py",
    "tier2_promql_test.py",
    "tier3_integration_test.py",
    "tier4_telemetry_test.py",
])

_DASHBOARDS_DATA = [
    "//gitops/argocd/platform/grafana-dashboards:grafana-dashboards-files",
]

_PY_DATA = [
    ":ci_pipelines_test.py",
    ":runner.sh",
    ":tier1_schema_test.py",
    ":tier2_promql_test.py",
    ":tier3_integration_test.py",
    ":tier4_telemetry_test.py",
] + _DASHBOARDS_DATA

rust_library(
    name = "grafana_dashboards_tests_lib",
    srcs = [
        "src/ci_pipelines.rs",
        "src/lib.rs",
        "src/runner.rs",
        "src/tier1.rs",
        "src/tier2.rs",
        "src/tier3.rs",
        "src/tier4.rs",
    ],
    crate_name = "grafana_dashboards_tests",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_test(
    name = "grafana_dashboards_tests_lib_test",
    size = "small",
    crate = ":grafana_dashboards_tests_lib",
    data = _DASHBOARDS_DATA,
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "runner",
    srcs = ["src/bin/runner.rs"],
    data = _PY_DATA,
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":grafana_dashboards_tests_lib"],
)

alias(
    name = "runner-rs",
    actual = ":runner",
)

alias(
    name = "runner_rs",
    actual = ":runner",
)

sh_binary(
    name = "runner-sh",
    srcs = ["runner.sh"],
    data = _PY_DATA,
)

alias(
    name = "runner_sh",
    actual = ":runner-sh",
)

rust_test(
    name = "tier1_schema_test",
    size = "small",
    srcs = ["src/bin/tier1_schema_test.rs"],
    data = _DASHBOARDS_DATA,
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    use_libtest_harness = False,
    deps = [":grafana_dashboards_tests_lib"],
)

rust_test(
    name = "tier2_promql_test",
    size = "small",
    srcs = ["src/bin/tier2_promql_test.rs"],
    data = _DASHBOARDS_DATA,
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    use_libtest_harness = False,
    deps = [":grafana_dashboards_tests_lib"],
)

rust_test(
    name = "tier3_integration_test",
    size = "small",
    srcs = ["src/bin/tier3_integration_test.rs"],
    data = _DASHBOARDS_DATA,
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    use_libtest_harness = False,
    deps = [":grafana_dashboards_tests_lib"],
)

rust_test(
    name = "tier4_telemetry_test",
    size = "medium",
    srcs = ["src/bin/tier4_telemetry_test.rs"],
    data = _DASHBOARDS_DATA,
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = ["manual"],
    use_libtest_harness = False,
    deps = [":grafana_dashboards_tests_lib"],
)

rust_test(
    name = "runner_test",
    size = "medium",
    srcs = ["src/bin/runner.rs"],
    data = _PY_DATA,
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = ["manual"],
    use_libtest_harness = False,
    deps = [":grafana_dashboards_tests_lib"],
)

rust_test(
    name = "ci_pipelines_test",
    size = "small",
    srcs = ["src/bin/ci_pipelines_test.rs"],
    data = _DASHBOARDS_DATA,
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    use_libtest_harness = False,
    deps = [":grafana_dashboards_tests_lib"],
)

rust_test(
    name = "parity_test",
    size = "small",
    srcs = ["src/bin/parity_test.rs"],
    data = _PY_DATA,
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    use_libtest_harness = False,
    deps = [":grafana_dashboards_tests_lib"],
)

# Retained original Python & Bash test suites for reference and parity checks
sh_test(
    name = "tier1_schema_py_test",
    size = "small",
    srcs = ["tier1_schema_test.py"],
    data = _PY_DATA,
)

sh_test(
    name = "tier2_promql_py_test",
    size = "small",
    srcs = ["tier2_promql_test.py"],
    data = _PY_DATA,
)

sh_test(
    name = "tier3_integration_py_test",
    size = "small",
    srcs = ["tier3_integration_test.py"],
    data = _PY_DATA,
)

sh_test(
    name = "tier4_telemetry_py_test",
    size = "medium",
    srcs = ["tier4_telemetry_test.py"],
    data = _PY_DATA,
    tags = ["manual"],
)

sh_test(
    name = "runner_sh_test",
    size = "medium",
    srcs = ["runner.sh"],
    data = _PY_DATA,
    tags = ["manual"],
)

sh_test(
    name = "ci_pipelines_py_test",
    size = "small",
    srcs = ["ci_pipelines_test.py"],
    data = _PY_DATA,
)
