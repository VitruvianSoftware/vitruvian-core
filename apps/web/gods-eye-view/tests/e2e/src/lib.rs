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

pub mod runner;
pub mod tier1;
pub mod tier2;
pub mod tier3;
pub mod tier4;
pub mod tier5;

#[cfg(test)]
mod tests {
    use super::runner::{
        OutputFormat, SuiteReport, TestContext, TestStatus, TierFilter, TierReport,
        find_repo_root, parse_args,
    };
    use std::time::Instant;

    fn make_ctx() -> TestContext {
        TestContext::new(find_repo_root(), false)
    }

    // --- CLI parsing tests ---

    #[test]
    fn parse_args_defaults() {
        let opts = parse_args(&[]).unwrap();
        assert_eq!(opts.tier_filter, TierFilter::All);
        assert_eq!(opts.format, OutputFormat::Text);
        assert!(!opts.strict);
        assert!(!opts.verbose);
    }

    #[test]
    fn parse_args_tier_single() {
        let args = vec!["--tier".into(), "3".into()];
        let opts = parse_args(&args).unwrap();
        assert_eq!(opts.tier_filter, TierFilter::Single(3));
    }

    #[test]
    fn parse_args_tier_all() {
        let args = vec!["--tier".into(), "all".into()];
        let opts = parse_args(&args).unwrap();
        assert_eq!(opts.tier_filter, TierFilter::All);
    }

    #[test]
    fn parse_args_invalid_tier() {
        let args = vec!["--tier".into(), "99".into()];
        assert!(parse_args(&args).is_err());
    }

    #[test]
    fn parse_args_missing_tier_value() {
        let args = vec!["--tier".into()];
        assert!(parse_args(&args).is_err());
    }

    #[test]
    fn parse_args_format_json() {
        let args = vec!["--format".into(), "json".into()];
        let opts = parse_args(&args).unwrap();
        assert_eq!(opts.format, OutputFormat::Json);
    }

    #[test]
    fn parse_args_format_tap() {
        let args = vec!["--format".into(), "tap".into()];
        let opts = parse_args(&args).unwrap();
        assert_eq!(opts.format, OutputFormat::Tap);
    }

    #[test]
    fn parse_args_invalid_format() {
        let args = vec!["--format".into(), "xml".into()];
        assert!(parse_args(&args).is_err());
    }

    #[test]
    fn parse_args_strict_flag() {
        let args = vec!["--strict".into()];
        let opts = parse_args(&args).unwrap();
        assert!(opts.strict);
    }

    #[test]
    fn parse_args_verbose_short() {
        let args = vec!["-v".into()];
        let opts = parse_args(&args).unwrap();
        assert!(opts.verbose);
    }

    #[test]
    fn parse_args_verbose_long() {
        let args = vec!["--verbose".into()];
        let opts = parse_args(&args).unwrap();
        assert!(opts.verbose);
    }

    #[test]
    fn parse_args_combined() {
        let args = vec![
            "--tier".into(),
            "2".into(),
            "--format".into(),
            "json".into(),
            "--strict".into(),
            "-v".into(),
        ];
        let opts = parse_args(&args).unwrap();
        assert_eq!(opts.tier_filter, TierFilter::Single(2));
        assert_eq!(opts.format, OutputFormat::Json);
        assert!(opts.strict);
        assert!(opts.verbose);
    }

    #[test]
    fn parse_args_unknown_option() {
        let args = vec!["--banana".into()];
        assert!(parse_args(&args).is_err());
    }

    // --- Output format tests ---

    #[test]
    fn output_format_from_str_text() {
        assert_eq!(OutputFormat::from_str("text"), Some(OutputFormat::Text));
    }

    #[test]
    fn output_format_from_str_tap() {
        assert_eq!(OutputFormat::from_str("tap"), Some(OutputFormat::Tap));
    }

    #[test]
    fn output_format_from_str_json() {
        assert_eq!(OutputFormat::from_str("json"), Some(OutputFormat::Json));
    }

    #[test]
    fn output_format_from_str_invalid() {
        assert_eq!(OutputFormat::from_str("yaml"), None);
    }

    // --- Strict mode tests ---

    #[test]
    fn skip_does_not_count_as_fail_in_normal_mode() {
        let mut ctx = TestContext::new(find_repo_root(), false);
        ctx.skip("TEST-SKIP", "should be skip", "test reason");
        assert_eq!(ctx.results[0].status, TestStatus::Skip);
    }

    #[test]
    fn skip_counts_as_fail_in_strict_mode() {
        let mut ctx = TestContext::new(find_repo_root(), true);
        ctx.skip("TEST-STRICT", "should fail in strict", "strict reason");
        assert_eq!(ctx.results[0].status, TestStatus::Fail);
    }

    // --- Repo root tests ---

    #[test]
    fn find_repo_root_returns_valid_directory() {
        let root = find_repo_root();
        assert!(root.is_dir(), "repo root must be a directory");
        assert!(
            root.join("MODULE.bazel").is_file()
                || root.join("pnpm-workspace.yaml").is_file()
                || root.join("go.work").is_file(),
            "repo root must contain a monorepo marker"
        );
    }

    // --- Per-tier smoke tests ---

    #[test]
    fn tier1_runs_without_panic() {
        let mut ctx = make_ctx();
        super::tier1::run(&mut ctx);
        assert_eq!(ctx.results.len(), 100, "tier1 must produce exactly 100 results");
    }

    #[test]
    fn tier2_runs_without_panic() {
        let mut ctx = make_ctx();
        super::tier2::run(&mut ctx);
        assert_eq!(ctx.results.len(), 100, "tier2 must produce exactly 100 results");
    }

    #[test]
    fn tier3_runs_without_panic() {
        let mut ctx = make_ctx();
        super::tier3::run(&mut ctx);
        assert_eq!(ctx.results.len(), 20, "tier3 must produce exactly 20 results");
    }

    #[test]
    fn tier4_runs_without_panic() {
        let mut ctx = make_ctx();
        super::tier4::run(&mut ctx);
        assert_eq!(ctx.results.len(), 5, "tier4 must produce exactly 5 results");
    }

    #[test]
    fn tier5_runs_without_panic() {
        let mut ctx = make_ctx();
        super::tier5::run(&mut ctx);
        assert_eq!(ctx.results.len(), 37, "tier5 must produce exactly 37 results");
    }

    // --- Full suite integration test ---

    #[test]
    fn run_all_tiers_262_tests_zero_failures() {
        let root = find_repo_root();
        let tier_defs: Vec<(u8, &str, fn(&mut TestContext))> = vec![
            (1, "Feature Coverage", super::tier1::run),
            (2, "Boundary Value Analysis", super::tier2::run),
            (3, "Cross-Feature Combinations", super::tier3::run),
            (4, "Real-World Application Scenarios", super::tier4::run),
            (5, "Adversarial Hardening", super::tier5::run),
        ];

        let suite_start = Instant::now();
        let mut tier_reports = Vec::new();
        for (tier, name, f) in &tier_defs {
            let mut ctx = TestContext::new(root.clone(), false);
            let start = Instant::now();
            f(&mut ctx);
            tier_reports.push(TierReport {
                tier: *tier,
                name: name.to_string(),
                results: ctx.results,
                duration_ms: start.elapsed().as_millis(),
            });
        }

        let report = SuiteReport {
            tiers: tier_reports,
            duration_ms: suite_start.elapsed().as_millis(),
        };

        assert_eq!(
            report.total_tests(),
            262,
            "full suite must have exactly 262 tests, got {}",
            report.total_tests()
        );
        assert_eq!(
            report.failed_tests(),
            0,
            "full suite must have 0 failures, got {}",
            report.failed_tests()
        );
    }

    // --- Test ID uniqueness ---

    #[test]
    fn all_tiers_have_unique_test_ids() {
        let mut ctx = make_ctx();
        super::tier1::run(&mut ctx);
        super::tier2::run(&mut ctx);
        super::tier3::run(&mut ctx);
        super::tier4::run(&mut ctx);
        super::tier5::run(&mut ctx);
        let ids: Vec<&str> = ctx.results.iter().map(|r| r.id.as_str()).collect();
        let mut seen = std::collections::HashSet::new();
        for id in &ids {
            assert!(seen.insert(*id), "Duplicate test ID: {}", id);
        }
    }

    // --- TierReport helpers ---

    #[test]
    fn tier_report_counts() {
        let report = TierReport {
            tier: 1,
            name: "Test".into(),
            results: vec![
                super::runner::TestCaseResult {
                    id: "T1".into(),
                    description: "pass".into(),
                    status: TestStatus::Pass,
                    detail: None,
                },
                super::runner::TestCaseResult {
                    id: "T2".into(),
                    description: "fail".into(),
                    status: TestStatus::Fail,
                    detail: None,
                },
                super::runner::TestCaseResult {
                    id: "T3".into(),
                    description: "skip".into(),
                    status: TestStatus::Skip,
                    detail: Some("reason".into()),
                },
            ],
            duration_ms: 0,
        };
        assert_eq!(report.total(), 3);
        assert_eq!(report.passed(), 2);
        assert_eq!(report.skipped(), 1);
        assert_eq!(report.failed(), 1);
        assert_eq!(report.status_label(), "FAILED");
    }

    #[test]
    fn tier_report_all_pass_label() {
        let report = TierReport {
            tier: 1,
            name: "Test".into(),
            results: vec![super::runner::TestCaseResult {
                id: "T1".into(),
                description: "pass".into(),
                status: TestStatus::Pass,
                detail: None,
            }],
            duration_ms: 0,
        };
        assert_eq!(report.status_label(), "PASSED");
    }

    // --- JSON helpers ---

    #[test]
    fn parse_json_string_basic() {
        let json = r#"{"name": "gods-eye-view", "version": "1.0.0"}"#;
        assert_eq!(
            super::runner::parse_json_string(json, "name"),
            Some("gods-eye-view")
        );
        assert_eq!(
            super::runner::parse_json_string(json, "version"),
            Some("1.0.0")
        );
    }

    #[test]
    fn parse_json_string_missing_key() {
        let json = r#"{"name": "test"}"#;
        assert_eq!(super::runner::parse_json_string(json, "absent"), None);
    }

    #[test]
    fn json_has_key_nested() {
        let json = r#"{"dependencies": {"cesium": "^1.124.0", "ws": "^8.18.0"}}"#;
        assert!(super::runner::json_has_key(json, "dependencies", "cesium"));
        assert!(super::runner::json_has_key(json, "dependencies", "ws"));
        assert!(!super::runner::json_has_key(json, "dependencies", "react"));
    }

    #[test]
    fn json_object_has_all_keys_check() {
        let json = r#"{"scripts": {"dev": "vite", "build": "vite build", "test": "vitest"}}"#;
        assert!(super::runner::json_object_has_all_keys(
            json,
            "scripts",
            &["dev", "build", "test"]
        ));
        assert!(!super::runner::json_object_has_all_keys(
            json,
            "scripts",
            &["dev", "build", "deploy"]
        ));
    }
}
