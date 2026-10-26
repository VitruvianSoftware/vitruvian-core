// Copyright (c) 2026 VitruvianSoftware
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

use gods_eye_view_e2e::runner::{
    SuiteReport, TestContext, TierFilter, TierReport,
    emit_report, find_repo_root, parse_args,
};
use std::time::Instant;

type TierFn = fn(&mut TestContext);

const TIERS: [(u8, &str, TierFn); 5] = [
    (1, "Feature Coverage", gods_eye_view_e2e::tier1::run),
    (2, "Boundary Value Analysis", gods_eye_view_e2e::tier2::run),
    (
        3,
        "Cross-Feature Combinations",
        gods_eye_view_e2e::tier3::run,
    ),
    (
        4,
        "Real-World Application Scenarios",
        gods_eye_view_e2e::tier4::run,
    ),
    (5, "Adversarial Hardening", gods_eye_view_e2e::tier5::run),
];

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let opts = match parse_args(&args) {
        Ok(o) => o,
        Err(e) => {
            eprintln!("Error: {}", e);
            std::process::exit(2);
        }
    };

    let root = find_repo_root();
    let suite_start = Instant::now();

    let tiers_to_run: Vec<(u8, &str, TierFn)> = match opts.tier_filter {
        TierFilter::All => TIERS.to_vec(),
        TierFilter::Single(n) => TIERS.iter().filter(|(t, _, _)| *t == n).cloned().collect(),
    };

    if tiers_to_run.is_empty() {
        eprintln!("Error: no matching tier found");
        std::process::exit(2);
    }

    let mut tier_reports = Vec::new();

    for (tier_num, tier_name, tier_fn) in &tiers_to_run {
        let mut ctx = TestContext::new(root.clone(), opts.strict);
        let start = Instant::now();
        tier_fn(&mut ctx);
        let duration = start.elapsed().as_millis();

        tier_reports.push(TierReport {
            tier: *tier_num,
            name: tier_name.to_string(),
            results: ctx.results,
            duration_ms: duration,
        });
    }

    let suite = SuiteReport {
        tiers: tier_reports,
        duration_ms: suite_start.elapsed().as_millis(),
    };

    emit_report(&suite, opts.format, opts.verbose);

    if suite.failed_tests() > 0 {
        std::process::exit(1);
    }
}
