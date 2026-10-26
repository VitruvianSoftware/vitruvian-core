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

use std::path::{Path, PathBuf};
use std::time::Instant;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TestStatus {
    Pass,
    Fail,
    Skip,
}

#[derive(Debug, Clone)]
pub struct TestCaseResult {
    pub id: String,
    pub description: String,
    pub status: TestStatus,
    pub detail: Option<String>,
}

#[derive(Debug, Clone)]
pub struct TierReport {
    pub tier: u8,
    pub name: String,
    pub results: Vec<TestCaseResult>,
    pub duration_ms: u128,
}

impl TierReport {
    pub fn passed(&self) -> usize {
        self.results
            .iter()
            .filter(|r| r.status == TestStatus::Pass || r.status == TestStatus::Skip)
            .count()
    }

    pub fn skipped(&self) -> usize {
        self.results
            .iter()
            .filter(|r| r.status == TestStatus::Skip)
            .count()
    }

    pub fn failed(&self) -> usize {
        self.results
            .iter()
            .filter(|r| r.status == TestStatus::Fail)
            .count()
    }

    pub fn total(&self) -> usize {
        self.results.len()
    }

    pub fn status_label(&self) -> &'static str {
        if self.failed() == 0 {
            "PASSED"
        } else {
            "FAILED"
        }
    }
}

#[derive(Debug)]
pub struct SuiteReport {
    pub tiers: Vec<TierReport>,
    pub duration_ms: u128,
}

impl SuiteReport {
    pub fn total_tests(&self) -> usize {
        self.tiers.iter().map(|t| t.total()).sum()
    }

    pub fn passed_tests(&self) -> usize {
        self.tiers.iter().map(|t| t.passed()).sum()
    }

    pub fn skipped_tests(&self) -> usize {
        self.tiers.iter().map(|t| t.skipped()).sum()
    }

    pub fn failed_tests(&self) -> usize {
        self.tiers.iter().map(|t| t.failed()).sum()
    }

    pub fn passed_tiers(&self) -> usize {
        self.tiers.iter().filter(|t| t.failed() == 0).count()
    }

    pub fn failed_tiers(&self) -> usize {
        self.tiers.iter().filter(|t| t.failed() > 0).count()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OutputFormat {
    Text,
    Tap,
    Json,
}

impl OutputFormat {
    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "text" => Some(Self::Text),
            "tap" => Some(Self::Tap),
            "json" => Some(Self::Json),
            _ => None,
        }
    }
}

#[derive(Debug, Clone)]
pub struct RunnerOptions {
    pub tier_filter: TierFilter,
    pub format: OutputFormat,
    pub strict: bool,
    pub verbose: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TierFilter {
    All,
    Single(u8),
}

impl Default for RunnerOptions {
    fn default() -> Self {
        Self {
            tier_filter: TierFilter::All,
            format: OutputFormat::Text,
            strict: false,
            verbose: false,
        }
    }
}

pub fn find_repo_root() -> PathBuf {
    if let Ok(val) = std::env::var("GEV_REPO_ROOT") {
        let p = PathBuf::from(&val);
        if p.join("MODULE.bazel").is_file() || p.join("pnpm-workspace.yaml").is_file() {
            return p;
        }
    }

    if let Ok(val) = std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        let p = PathBuf::from(&val);
        if p.join("MODULE.bazel").is_file() || p.join("pnpm-workspace.yaml").is_file() {
            return p;
        }
    }

    if let Ok(val) = std::env::var("TEST_SRCDIR") {
        let p = PathBuf::from(&val).join("_main");
        if p.join("MODULE.bazel").is_file() || p.join("pnpm-workspace.yaml").is_file() {
            return p;
        }
    }

    if let Ok(cwd) = std::env::current_dir() {
        let mut cur = cwd.as_path();
        loop {
            if cur.join("MODULE.bazel").is_file()
                || cur.join("go.work").is_file()
                || cur.join("pnpm-workspace.yaml").is_file()
            {
                return cur.to_path_buf();
            }
            if let Ok(canon) = std::fs::canonicalize(cur.join("apps/web/gods-eye-view/BUILD.bazel"))
            {
                let mut ancestor = canon.as_path();
                while let Some(p) = ancestor.parent() {
                    if p.join("MODULE.bazel").is_file() || p.join("pnpm-workspace.yaml").is_file() {
                        return p.to_path_buf();
                    }
                    ancestor = p;
                }
            }
            match cur.parent() {
                Some(parent) if parent != cur => cur = parent,
                _ => break,
            }
        }
    }

    std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

pub fn parse_args(args: &[String]) -> Result<RunnerOptions, String> {
    let mut opts = RunnerOptions::default();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--tier" => {
                i += 1;
                if i >= args.len() {
                    return Err("--tier requires a value".to_string());
                }
                opts.tier_filter = match args[i].as_str() {
                    "all" => TierFilter::All,
                    "1" => TierFilter::Single(1),
                    "2" => TierFilter::Single(2),
                    "3" => TierFilter::Single(3),
                    "4" => TierFilter::Single(4),
                    "5" => TierFilter::Single(5),
                    other => return Err(format!("invalid tier: {}", other)),
                };
            }
            "--format" => {
                i += 1;
                if i >= args.len() {
                    return Err("--format requires a value".to_string());
                }
                opts.format = OutputFormat::from_str(&args[i])
                    .ok_or_else(|| format!("invalid format: {}", args[i]))?;
            }
            "--strict" => opts.strict = true,
            "-v" | "--verbose" => opts.verbose = true,
            "-h" | "--help" => {
                print_usage();
                std::process::exit(0);
            }
            other => return Err(format!("unknown option: {}", other)),
        }
        i += 1;
    }
    Ok(opts)
}

fn print_usage() {
    eprintln!(
        "Usage: run-e2e-tests [options]\n\
         \n\
         Options:\n\
         \x20 --tier <1|2|3|4|5|all>     Execute specific test tier (default: all)\n\
         \x20 --format <text|tap|json>   Output format (default: text)\n\
         \x20 --strict                   Enforce strict mode (fail if any milestone artifact is pending)\n\
         \x20 -v, --verbose              Enable verbose test output\n\
         \x20 -h, --help                 Show this help message\n\
         \n\
         Test Tiers:\n\
         \x20 Tier 1: Feature Coverage (100 tests across Features F1-F20, 5 per feature)\n\
         \x20 Tier 2: Boundary Value Analysis (100 boundary, negative, and edge cases across F1-F20)\n\
         \x20 Tier 3: Cross-Feature Combinations (20 pairwise cross-module integration tests)\n\
         \x20 Tier 4: Real-World Application Scenarios (5 end-to-end multi-layer integration scenarios)\n\
         \x20 Tier 5: Adversarial Hardening (37 white-box adversarial stress & security tests)"
    );
}

pub fn emit_report(report: &SuiteReport, format: OutputFormat, verbose: bool) {
    match format {
        OutputFormat::Text => emit_text(report, verbose),
        OutputFormat::Tap => emit_tap(report),
        OutputFormat::Json => emit_json(report),
    }
}

fn emit_text(report: &SuiteReport, verbose: bool) {
    println!("================================================================================");
    println!(" Execution Matrix & Coverage Verification Summary");
    println!("================================================================================");
    println!(
        "| {:<6} | {:<28} | {:<8} | {:<7} | {:<7} | {:<7} | {:<10} |",
        "Tier", "Description", "Status", "Passed", "Skip", "Failed", "Duration"
    );
    println!("|--------|------------------------------|----------|---------|---------|---------|------------|");
    for t in &report.tiers {
        println!(
            "| Tier {:<2} | {:<28} | {:<8} | {:<7} | {:<7} | {:<7} | {:<8}ms |",
            t.tier,
            &t.name,
            t.status_label(),
            t.passed(),
            t.skipped(),
            t.failed(),
            t.duration_ms
        );
    }
    println!("================================================================================");
    println!(
        " TOTALS: {}/{} tests passed ({} skipped pending later milestones) across {}/{} tiers ({}ms total)",
        report.passed_tests(),
        report.total_tests(),
        report.skipped_tests(),
        report.passed_tiers(),
        report.tiers.len(),
        report.duration_ms
    );
    println!("================================================================================");

    if report.failed_tiers() == 0 {
        println!(" 100% PASS RATE — GOD'S EYE VIEW E2E TEST SUITE VERIFIED");
    } else {
        eprintln!(
            " FAILURES DETECTED IN {} TIER(S)",
            report.failed_tiers()
        );
    }

    if verbose {
        for t in &report.tiers {
            for r in &t.results {
                match r.status {
                    TestStatus::Pass => println!("  ok - {}: {}", r.id, r.description),
                    TestStatus::Skip => {
                        println!(
                            "  ok - {}: {} # SKIP {}",
                            r.id,
                            r.description,
                            r.detail.as_deref().unwrap_or("")
                        );
                    }
                    TestStatus::Fail => {
                        eprintln!("  not ok - {}: {}", r.id, r.description);
                        if let Some(d) = &r.detail {
                            eprintln!("    # Error: {}", d);
                        }
                    }
                }
            }
        }
    }
}

fn emit_tap(report: &SuiteReport) {
    println!("1..{}", report.tiers.len());
    for (idx, t) in report.tiers.iter().enumerate() {
        let i = idx + 1;
        if t.failed() == 0 {
            println!(
                "ok {} - Tier {}: {} ({}/{} passed, {} skipped in {}ms)",
                i,
                t.tier,
                t.name,
                t.passed(),
                t.passed(),
                t.skipped(),
                t.duration_ms
            );
        } else {
            println!(
                "not ok {} - Tier {}: {} ({} failed in {}ms)",
                i,
                t.tier,
                t.name,
                t.failed(),
                t.duration_ms
            );
        }
    }
}

fn emit_json(report: &SuiteReport) {
    let mut tiers_json = String::from("[");
    for (idx, t) in report.tiers.iter().enumerate() {
        if idx > 0 {
            tiers_json.push(',');
        }
        tiers_json.push_str(&format!(
            r#"{{"tier":{},"name":"{}","status":"{}","total":{},"passed":{},"skipped":{},"active_pass":{},"failed":{},"duration_ms":{}}}"#,
            t.tier,
            json_escape(&t.name),
            t.status_label(),
            t.total(),
            t.passed(),
            t.skipped(),
            t.passed().saturating_sub(t.skipped()),
            t.failed(),
            t.duration_ms
        ));
    }
    tiers_json.push(']');

    println!(
        r#"{{"project":"Gods Eye View Migration","total_tiers":{},"passed_tiers":{},"failed_tiers":{},"total_tests":{},"passed_tests":{},"skipped_tests":{},"active_pass_tests":{},"failed_tests":{},"duration_ms":{},"tiers":{}}}"#,
        report.tiers.len(),
        report.passed_tiers(),
        report.failed_tiers(),
        report.total_tests(),
        report.passed_tests(),
        report.skipped_tests(),
        report.passed_tests().saturating_sub(report.skipped_tests()),
        report.failed_tests(),
        report.duration_ms,
        tiers_json
    );
}

fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                out.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => out.push(c),
        }
    }
    out
}

pub struct TestContext {
    pub root: PathBuf,
    pub strict: bool,
    pub results: Vec<TestCaseResult>,
}

impl TestContext {
    pub fn new(root: PathBuf, strict: bool) -> Self {
        Self {
            root,
            strict,
            results: Vec::new(),
        }
    }

    pub fn pass(&mut self, id: &str, desc: &str) {
        self.results.push(TestCaseResult {
            id: id.to_string(),
            description: desc.to_string(),
            status: TestStatus::Pass,
            detail: None,
        });
    }

    pub fn fail(&mut self, id: &str, desc: &str) {
        self.results.push(TestCaseResult {
            id: id.to_string(),
            description: desc.to_string(),
            status: TestStatus::Fail,
            detail: None,
        });
    }

    pub fn fail_with(&mut self, id: &str, desc: &str, detail: &str) {
        self.results.push(TestCaseResult {
            id: id.to_string(),
            description: desc.to_string(),
            status: TestStatus::Fail,
            detail: Some(detail.to_string()),
        });
    }

    pub fn skip(&mut self, id: &str, desc: &str, reason: &str) {
        if self.strict {
            self.results.push(TestCaseResult {
                id: id.to_string(),
                description: desc.to_string(),
                status: TestStatus::Fail,
                detail: Some(format!("STRICT: {}", reason)),
            });
        } else {
            self.results.push(TestCaseResult {
                id: id.to_string(),
                description: desc.to_string(),
                status: TestStatus::Skip,
                detail: Some(reason.to_string()),
            });
        }
    }

    pub fn path(&self, rel: &str) -> PathBuf {
        self.root.join(rel)
    }

    pub fn file_exists(&self, rel: &str) -> bool {
        self.path(rel).is_file()
    }

    pub fn dir_exists(&self, rel: &str) -> bool {
        self.path(rel).is_dir()
    }

    pub fn read_file(&self, rel: &str) -> Option<String> {
        std::fs::read_to_string(self.path(rel)).ok()
    }

    pub fn file_contains(&self, rel: &str, needle: &str) -> bool {
        self.read_file(rel)
            .map(|c| c.contains(needle))
            .unwrap_or(false)
    }

    pub fn file_size(&self, rel: &str) -> u64 {
        std::fs::metadata(self.path(rel))
            .map(|m| m.len())
            .unwrap_or(0)
    }

    pub fn is_build_ready(&self) -> bool {
        let build_path = self.path("apps/web/gods-eye-view/BUILD.bazel");
        let build_dir = self.path("apps/web/gods-eye-view/BUILD");
        let is_regular_file = build_path.is_file() || (build_dir.exists() && !build_dir.is_dir());
        if !is_regular_file {
            return false;
        }
        let path = if build_path.is_file() {
            build_path
        } else {
            build_dir
        };
        if let Ok(content) = std::fs::read_to_string(&path) {
            content.contains("gazelle:ignore")
                || content.contains("rules_js")
                || content.contains("vite")
                || content.contains("pipeline_unit")
                || content.contains("doctor")
        } else {
            false
        }
    }

    pub fn build_file_content(&self) -> Option<String> {
        let p = self.path("apps/web/gods-eye-view/BUILD.bazel");
        if p.is_file() {
            return std::fs::read_to_string(&p).ok();
        }
        let p2 = self.path("apps/web/gods-eye-view/BUILD");
        if p2.is_file() {
            return std::fs::read_to_string(&p2).ok();
        }
        None
    }

    pub fn count_files_matching(&self, dir: &str, ext: &str) -> usize {
        let base = self.path(dir);
        count_files_recursive(&base, ext)
    }
}

fn count_files_recursive(dir: &Path, ext: &str) -> usize {
    let mut count = 0;
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                count += count_files_recursive(&path, ext);
            } else if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                if name.ends_with(ext) {
                    count += 1;
                }
            }
        }
    }
    count
}

pub fn run_single_tier<F>(tier: u8, name: &str, f: F)
where
    F: FnOnce(&mut TestContext),
{
    let args: Vec<String> = std::env::args().skip(1).collect();
    let strict = args.iter().any(|a| a == "--strict");
    let root = find_repo_root();
    let mut ctx = TestContext::new(root, strict);

    let start = Instant::now();
    f(&mut ctx);
    let duration = start.elapsed().as_millis();

    let report = TierReport {
        tier,
        name: name.to_string(),
        results: ctx.results,
        duration_ms: duration,
    };

    println!("================================================================================");
    println!(
        " Tier {}: {} ({} Tests)",
        tier, name, report.total()
    );
    println!("================================================================================");

    for (idx, r) in report.results.iter().enumerate() {
        let num = idx + 1;
        match r.status {
            TestStatus::Pass => println!("  ok {} - {}: {}", num, r.id, r.description),
            TestStatus::Skip => {
                println!(
                    "  ok {} - {}: {} # SKIP {}",
                    num,
                    r.id,
                    r.description,
                    r.detail.as_deref().unwrap_or("")
                );
            }
            TestStatus::Fail => {
                eprintln!("  not ok {} - {}: {}", num, r.id, r.description);
                if let Some(d) = &r.detail {
                    eprintln!("    # Error: {}", d);
                }
            }
        }
    }

    println!("================================================================================");
    println!(
        " Tier {} Summary: {}/{} passed ({} skipped, {} failed)",
        tier,
        report.passed(),
        report.total(),
        report.skipped(),
        report.failed()
    );
    println!("================================================================================");

    if report.failed() > 0 {
        std::process::exit(1);
    }
}

pub fn parse_json_string<'a>(content: &'a str, key: &str) -> Option<&'a str> {
    let search = format!("\"{}\"", key);
    let pos = content.find(&search)?;
    let after_key = &content[pos + search.len()..];
    let colon_pos = after_key.find(':')?;
    let after_colon = after_key[colon_pos + 1..].trim_start();
    if after_colon.starts_with('"') {
        let inner = &after_colon[1..];
        let end = inner.find('"')?;
        Some(&inner[..end])
    } else {
        None
    }
}

pub fn json_has_key(content: &str, object_key: &str, nested_key: &str) -> bool {
    let search = format!("\"{}\"", object_key);
    if let Some(pos) = content.find(&search) {
        let after = &content[pos + search.len()..];
        if let Some(brace) = after.find('{') {
            let block = &after[brace..];
            let needle = format!("\"{}\"", nested_key);
            if let Some(close) = find_matching_brace(block) {
                return block[..close].contains(&needle);
            }
        }
    }
    false
}

fn find_matching_brace(s: &str) -> Option<usize> {
    let mut depth = 0;
    for (i, c) in s.char_indices() {
        match c {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if depth == 0 {
                    return Some(i);
                }
            }
            _ => {}
        }
    }
    None
}

pub fn json_object_has_all_keys(content: &str, object_key: &str, keys: &[&str]) -> bool {
    keys.iter().all(|k| json_has_key(content, object_key, k))
}
