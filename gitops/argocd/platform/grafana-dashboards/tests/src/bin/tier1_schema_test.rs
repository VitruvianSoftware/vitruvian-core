// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Binary test entrypoint for Tier 1 Grafana dashboard schema validation.

fn main() {
    std::process::exit(grafana_dashboards_tests::tier1::run_tier1_tests());
}
