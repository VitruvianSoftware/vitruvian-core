// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Binary entrypoint for the Grafana Dashboards E2E master test runner.

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    std::process::exit(grafana_dashboards_tests::runner::run(&args));
}
