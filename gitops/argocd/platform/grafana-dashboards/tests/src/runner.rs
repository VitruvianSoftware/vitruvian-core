// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Master E2E Dashboard Test Suite Runner (`runner.sh` port).
//!
//! Orchestrates execution of Tiers 1-4 for Grafana Dashboards, aggregates verdicts,
//! and emits TAP / JSON / Text reports.

use std::env;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::Serialize;

use crate::{find_dashboards_dir, tier1, tier2, tier3, tier4};

const RULE: &str =
    "================================================================================";

pub const TIERS: [(&str, &str); 4] = [
    ("1", "Schema & Structure"),
    ("2", "PromQL & Metric Integrity"),
    ("3", "GitOps & Consistency"),
    ("4", "Live Thanos Telemetry"),
];

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TierResult {
    pub num: String,
    pub name: String,
    pub passed: bool,
    pub ok_count: u64,
    pub fail_count: u64,
    pub duration_ms: i64,
}

#[derive(Serialize)]
struct JsonTier<'a> {
    tier: i64,
    name: &'a str,
    status: &'a str,
    passed: u64,
    failed: u64,
    duration_ms: i64,
}

#[derive(Serialize)]
struct JsonPayload<'a> {
    suite: &'static str,
    total_tiers: usize,
    passed_tiers: usize,
    failed_tiers: usize,
    total_tests: u64,
    passed_tests: u64,
    failed_tests: u64,
    duration_ms: i64,
    tiers: Vec<JsonTier<'a>>,
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn prog_basename() -> String {
    env::args()
        .next()
        .and_then(|p| {
            Path::new(&p)
                .file_name()
                .map(|s| s.to_string_lossy().into_owned())
        })
        .unwrap_or_else(|| "runner".to_string())
}

pub fn usage_text(prog: &str) -> String {
    format!(
        "Usage: {} [options]

Options:
  --tier <1|2|3|4|all>       Execute specific test tier (default: all)
  --format <text|tap|json>   Output format (default: text)
  --allow-offline            Allow skipping Tier 4 live queries if cluster is unreachable
  -v, --verbose              Enable verbose test output
  -h, --help                 Show this help message

Test Tiers:
  Tier 1: Schema & Structure Validation (JSON syntax, UIDs, variables, panels, gridPos)
  Tier 2: PromQL Syntax & Metric Integrity (syntax parse, time units ms vs s, aggregations)
  Tier 3: GitOps Integration & Consistency (kustomization.yaml, sidecar discoverability)
  Tier 4: Live Telemetry Verification (instant queries against Thanos Querier)
",
        prog
    )
}

/// Resolve workspace root walking symlinks and parent directories for `MODULE.bazel` or `go.work`.
pub fn resolve_workspace_root(exe_path: &Path) -> PathBuf {
    let resolved = fs::canonicalize(exe_path).unwrap_or_else(|_| exe_path.to_path_buf());
    let mut cur = resolved.parent().map(Path::to_path_buf);
    while let Some(dir) = cur {
        if dir.join("MODULE.bazel").is_file() || dir.join("go.work").is_file() {
            return dir;
        }
        cur = dir.parent().map(Path::to_path_buf);
    }
    if let Ok(bwd) = env::var("BUILD_WORKSPACE_DIRECTORY") {
        if !bwd.is_empty() {
            return PathBuf::from(bwd);
        }
    }
    env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

/// Count TAP lines matching awk's `/^[[:space:]]*ok /` or `/^[[:space:]]*not ok /`.
pub fn count_tap_prefix(output: &str, prefix: &str) -> u64 {
    output
        .lines()
        .filter(|line| {
            let trimmed = line.trim_start_matches([' ', '\t', '\x0b', '\x0c', '\r']);
            trimmed
                .strip_prefix(prefix)
                .map(|rest| rest.starts_with(' '))
                .unwrap_or(false)
        })
        .count() as u64
}

pub fn format_json_report(results: &[TierResult], total_duration_ms: i64) -> String {
    let tiers: Vec<JsonTier> = results
        .iter()
        .map(|r| JsonTier {
            tier: r.num.parse().unwrap_or(0),
            name: &r.name,
            status: if r.passed { "PASSED" } else { "FAILED" },
            passed: r.ok_count,
            failed: r.fail_count,
            duration_ms: r.duration_ms,
        })
        .collect();
    let payload = JsonPayload {
        suite: "grafana_dashboards_e2e",
        total_tiers: tiers.len(),
        passed_tiers: tiers.iter().filter(|t| t.status == "PASSED").count(),
        failed_tiers: tiers.iter().filter(|t| t.status == "FAILED").count(),
        total_tests: tiers.iter().map(|t| t.passed + t.failed).sum(),
        passed_tests: tiers.iter().map(|t| t.passed).sum(),
        failed_tests: tiers.iter().map(|t| t.failed).sum(),
        duration_ms: total_duration_ms,
        tiers,
    };
    format!(
        "{}\n",
        serde_json::to_string_pretty(&payload).unwrap_or_default()
    )
}

pub fn format_tap_report(results: &[TierResult]) -> String {
    let mut s = format!("1..{}\n", results.len());
    for (idx, r) in results.iter().enumerate() {
        let n = idx + 1;
        if r.passed {
            s.push_str(&format!(
                "ok {} - Tier {}: {} ({}/{} passed in {}ms)\n",
                n, r.num, r.name, r.ok_count, r.ok_count, r.duration_ms
            ));
        } else {
            s.push_str(&format!(
                "not ok {} - Tier {}: {} ({} failed in {}ms)\n",
                n, r.num, r.name, r.fail_count, r.duration_ms
            ));
        }
    }
    s
}

pub fn format_text_report(results: &[TierResult], total_duration_ms: i64) -> String {
    let total_tiers = results.len();
    let passed_tiers = results.iter().filter(|r| r.passed).count();
    let failed_tiers = total_tiers - passed_tiers;
    let passed_test_count: u64 = results.iter().map(|r| r.ok_count).sum();
    let total_test_count: u64 = results.iter().map(|r| r.ok_count + r.fail_count).sum();

    let mut s = String::new();
    s.push('\n');
    s.push_str(RULE);
    s.push_str("\n Execution Matrix & Dashboard Verification Summary\n");
    s.push_str(RULE);
    s.push('\n');
    s.push_str(&format!(
        "| {:<6} | {:<28} | {:<8} | {:<8} | {:<8} | {:<10} |\n",
        "Tier", "Description", "Status", "Passed", "Failed", "Duration"
    ));
    s.push_str(
        "|--------|------------------------------|----------|----------|----------|------------|\n",
    );
    for r in results {
        let status_str = if r.passed { "PASSED" } else { "FAILED" };
        s.push_str(&format!(
            "| Tier {:<2} | {:<28} | {:<8} | {:<8} | {:<8} | {:<8}ms |\n",
            r.num, r.name, status_str, r.ok_count, r.fail_count, r.duration_ms
        ));
    }
    s.push_str(RULE);
    s.push('\n');
    s.push_str(&format!(
        " TOTALS: {}/{} tests passed across {}/{} tiers ({}ms total)\n",
        passed_test_count, total_test_count, passed_tiers, total_tiers, total_duration_ms
    ));
    s.push_str(RULE);
    s.push('\n');

    if failed_tiers == 0 {
        s.push_str(" 🎉 100% PASS RATE — GRAFANA DASHBOARDS VERIFIED FOR PRODUCTION\n");
    } else {
        s.push_str(&format!(
            " ❌ FAILURES DETECTED IN {} TIER(S)\n",
            failed_tiers
        ));
    }
    s
}

fn execute_tier(
    tier_num: &str,
    allow_offline: bool,
    dashboards_dir: Option<&Path>,
) -> (i32, String) {
    if let Some(dir) = dashboards_dir {
        let (code, mut out) = match tier_num {
            "1" => tier1::run_tier1_on_dir(dir),
            "2" => tier2::run_tier2_on_dir(dir),
            "3" => tier3::run_tier3_on_dir(dir),
            "4" => tier4::run_tier4_on_dir(dir, allow_offline),
            _ => (1, format!("Unknown tier: {}", tier_num)),
        };
        while out.ends_with('\n') {
            out.pop();
        }
        return (code, out);
    }

    (
        1,
        "Could not locate gitops/argocd/platform/grafana-dashboards directory".to_string(),
    )
}

/// Run the master suite with the given CLI arguments.
pub fn run(args: &[String]) -> i32 {
    let prog = prog_basename();
    let exe_path = env::args()
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("runner"));

    let root = match env::var("BUILD_WORKSPACE_DIRECTORY") {
        Ok(val) if !val.is_empty() => PathBuf::from(val),
        _ => resolve_workspace_root(&exe_path),
    };
    let _ = env::set_current_dir(&root);

    let mut tier_filter = "all".to_string();
    let mut format = "text".to_string();
    let mut verbose = false;
    let mut allow_offline = false;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--tier" => {
                if let Some(v) = args.get(i + 1) {
                    tier_filter = v.clone();
                    i += 2;
                } else {
                    eprintln!("{}: line 60: $2: unbound variable", prog);
                    return 1;
                }
            }
            "--format" => {
                if let Some(v) = args.get(i + 1) {
                    format = v.clone();
                    i += 2;
                } else {
                    eprintln!("{}: line 64: $2: unbound variable", prog);
                    return 1;
                }
            }
            "--allow-offline" => {
                allow_offline = true;
                i += 1;
            }
            "-v" | "--verbose" => {
                verbose = true;
                i += 1;
            }
            "-h" | "--help" => {
                print!("{}", usage_text(&prog));
                return 0;
            }
            other => {
                eprintln!("ERROR: Unknown option: {}", other);
                print!("{}", usage_text(&prog));
                return 1;
            }
        }
    }

    let start_time = now_ms();

    println!("{}", RULE);
    println!(" Grafana Production Dashboards — E2E Master Test Suite");
    println!(" Working Directory: {}", root.display());
    println!(" Tier Selection:    {}", tier_filter);
    println!("{}", RULE);
    let _ = std::io::stdout().flush();

    let dashboards_dir = find_dashboards_dir().ok();
    let mut results: Vec<TierResult> = Vec::new();

    for (tier_num, tier_name) in TIERS {
        if tier_filter != "all" && tier_filter != tier_num {
            continue;
        }
        let t_start = now_ms();
        let (status, out) = execute_tier(tier_num, allow_offline, dashboards_dir.as_deref());
        let t_dur = now_ms() - t_start;

        let passed_cnt = count_tap_prefix(&out, "ok");
        let failed_cnt = count_tap_prefix(&out, "not ok");
        let tier_passed = status == 0 && failed_cnt == 0;

        results.push(TierResult {
            num: tier_num.to_string(),
            name: tier_name.to_string(),
            passed: tier_passed,
            ok_count: passed_cnt,
            fail_count: failed_cnt,
            duration_ms: t_dur,
        });

        if tier_passed {
            if verbose {
                println!("{}", out);
            }
        } else {
            eprintln!("{}", out);
        }
    }

    let total_duration = now_ms() - start_time;

    if format == "json" {
        print!("{}", format_json_report(&results, total_duration));
    } else if format == "tap" {
        print!("{}", format_tap_report(&results));
    } else {
        print!("{}", format_text_report(&results, total_duration));
    }

    if results.iter().any(|r| !r.passed) {
        1
    } else {
        0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_count_tap_prefix() {
        let sample = "TAP version 13\nok 1 - first\n  ok 2 - second\nnot ok 3 - third\n# ok 4";
        assert_eq!(count_tap_prefix(sample, "ok"), 2);
        assert_eq!(count_tap_prefix(sample, "not ok"), 1);
    }

    #[test]
    fn test_reports_formatting() {
        let tiers = vec![
            TierResult {
                num: "1".to_string(),
                name: "Schema & Structure".to_string(),
                passed: true,
                ok_count: 80,
                fail_count: 0,
                duration_ms: 5,
            },
            TierResult {
                num: "2".to_string(),
                name: "PromQL & Metric Integrity".to_string(),
                passed: false,
                ok_count: 29,
                fail_count: 1,
                duration_ms: 7,
            },
        ];

        let tap = format_tap_report(&tiers);
        assert_eq!(
            tap,
            "1..2\nok 1 - Tier 1: Schema & Structure (80/80 passed in 5ms)\nnot ok 2 - Tier 2: PromQL & Metric Integrity (1 failed in 7ms)\n"
        );

        let json_str = format_json_report(&tiers, 12);
        assert!(json_str.contains("\"suite\": \"grafana_dashboards_e2e\""));
        assert!(json_str.contains("\"total_tests\": 110"));
        assert!(json_str.contains("\"passed_tests\": 109"));
        assert!(json_str.contains("\"failed_tests\": 1"));

        let text = format_text_report(&tiers, 12);
        assert!(text.contains("TOTALS: 109/110 tests passed across 1/2 tiers (12ms total)"));
        assert!(text.contains("❌ FAILURES DETECTED IN 1 TIER(S)"));
    }
}
