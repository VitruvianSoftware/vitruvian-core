// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Binary test entrypoint for Tier 2 Grafana dashboard PromQL validation.

fn main() {
    std::process::exit(grafana_dashboards_tests::tier2::run_tier2_tests());
}
