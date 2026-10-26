// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Binary test entrypoint for Tier 3 Grafana dashboard GitOps integration validation.

fn main() {
    std::process::exit(grafana_dashboards_tests::tier3::run_tier3_tests());
}
