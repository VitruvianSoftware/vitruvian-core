// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

use std::time::Instant;

use firmware_tests::{
    test_agent_ci, test_catalog, test_challenger_m2, test_challenger_m3,
    test_challenger_m3_firmware, test_cloud_ci, test_net_telemetry, test_orientation,
    test_power_battery, test_profiles, test_settings_toggles, test_stress_firmware,
    test_wifi_provisioning,
};

fn main() {
    let suites: &[(&str, fn() -> usize)] = &[
        ("test_agent_ci", test_agent_ci::run_suite),
        ("test_catalog", test_catalog::run_suite),
        ("test_challenger_m2", test_challenger_m2::run_suite),
        ("test_challenger_m3", test_challenger_m3::run_suite),
        (
            "test_challenger_m3_firmware",
            test_challenger_m3_firmware::run_suite,
        ),
        ("test_cloud_ci", test_cloud_ci::run_suite),
        ("test_net_telemetry", test_net_telemetry::run_suite),
        ("test_orientation", test_orientation::run_suite),
        ("test_power_battery", test_power_battery::run_suite),
        ("test_profiles", test_profiles::run_suite),
        ("test_settings_toggles", test_settings_toggles::run_suite),
        ("test_stress_firmware", test_stress_firmware::run_suite),
        ("test_wifi_provisioning", test_wifi_provisioning::run_suite),
    ];

    let total_start = Instant::now();
    let mut total_checks = 0usize;

    for (name, runner) in suites {
        let start = Instant::now();
        let checks = runner();
        let elapsed_ms = start.elapsed().as_secs_f64() * 1000.0;
        total_checks += checks;
        println!("{:<30} {:>3} checks  {:>8.3} ms", name, checks, elapsed_ms);
    }

    let total_ms = total_start.elapsed().as_secs_f64() * 1000.0;
    println!(
        "---------------------------------------------------------------\nTotal: {} suites, {} checks passed in {:.3} ms",
        suites.len(),
        total_checks,
        total_ms
    );
}
