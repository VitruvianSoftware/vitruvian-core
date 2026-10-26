// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Binary test entrypoint for Tier 4 Grafana dashboard live telemetry validation.

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    std::process::exit(grafana_dashboards_tests::tier4::run_tier4_cli(&args));
}
