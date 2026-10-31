# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

package(default_visibility = ["//visibility:public"])

_DASHBOARDS_DATA = [
    "//gitops/argocd/platform/grafana-dashboards:grafana-dashboards-files",
]

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
    data = _DASHBOARDS_DATA,
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":grafana_dashboards_tests_lib"],
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
    data = _DASHBOARDS_DATA,
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
