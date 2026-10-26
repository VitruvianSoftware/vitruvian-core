// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Binary test entrypoint for CI pipelines Grafana dashboard validation.

fn main() {
    std::process::exit(grafana_dashboards_tests::ci_pipelines::run_ci_pipelines_test());
}
