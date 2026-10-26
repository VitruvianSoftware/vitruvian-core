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

//! pipeline-mouse-daemon.sh in Rust: monitors the GitHub main branch and
//! updates the GravaStar mouse RGB indicator based on pipeline status.
//!
//! LED State Matrix:
//!   - Pulsing Yellow: in-progress, all checks green so far.
//!   - Pulsing Red:    a check failed, more still running in-flight.
//!   - Solid Red:      pipeline completed with at least one failure.
//!   - Solid Green:    pipeline completed, all checks passed.

use crate::evaluate::evaluate_runs_json;
use crate::sh;

use std::io::Write;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};

static INTERRUPTED: AtomicBool = AtomicBool::new(false);

extern "C" fn handle_signal(_: i32) {
    INTERRUPTED.store(true, Ordering::SeqCst);
}

extern "C" {
    fn signal(sig: i32, handler: extern "C" fn(i32)) -> *const ();
}

const NO_RUNS_JSON: &str = r#"{"total_count":0,"workflow_runs":[]}"#;
const STATUS_OUT_PATH: &str = "/tmp/pipeline-status-out.txt";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LedSignal {
    PulsingRed,
    SolidRed,
    PulsingYellow,
    SolidGreen,
    Warning,
}

impl LedSignal {
    pub fn name(&self) -> &'static str {
        match self {
            Self::PulsingRed => "pulsing_red",
            Self::SolidRed => "solid_red",
            Self::PulsingYellow => "pulsing_yellow",
            Self::SolidGreen => "solid_green",
            Self::Warning => "warning",
        }
    }
}

pub struct DaemonConfig {
    pub interval: u64,
    pub repo: String,
    pub branch: String,
    pub gravastar_bin: String,
    pub once: bool,
    pub max_iterations: Option<u64>,
    pub pipeline_cmd: Option<String>,
}

struct PollResult {
    rc: i32,
    failed_count: u32,
    in_flight_count: u32,
    summary: String,
}

/// Equivalent to `grep -o -E '[0-9]+ <word>' | head -n 1 | awk '{print $1}'`.
pub fn parse_count(text: &str, word: &str) -> u32 {
    let target = format!(" {word}");
    for line in text.lines() {
        let mut pos = 0;
        while pos < line.len() {
            match line[pos..].find(&target) {
                Some(idx) => {
                    let abs = pos + idx;
                    let mut start = abs;
                    while start > 0 && line.as_bytes()[start - 1].is_ascii_digit() {
                        start -= 1;
                    }
                    if start < abs {
                        if let Ok(n) = line[start..abs].parse::<u32>() {
                            return n;
                        }
                    }
                    pos = abs + target.len();
                }
                None => break,
            }
        }
    }
    0
}

/// Determine LED signal from pipeline status, matching the shell's if/elif chain.
pub fn determine_signal(rc: i32, failed_count: u32, in_flight_count: u32) -> LedSignal {
    if failed_count > 0 && in_flight_count > 0 {
        LedSignal::PulsingRed
    } else if failed_count > 0 {
        LedSignal::SolidRed
    } else if in_flight_count > 0 {
        LedSignal::PulsingYellow
    } else if rc == 0 {
        LedSignal::SolidGreen
    } else {
        LedSignal::Warning
    }
}

fn run_inherit(program: &str, args: &[&str]) -> i32 {
    let _ = std::io::stdout().flush();
    match Command::new(program)
        .args(args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
    {
        Ok(status) => sh::status_code(status),
        Err(err) => sh::spawn_failure_code(&err),
    }
}

/// Apply LED signal to the GravaStar mouse, matching the shell's case branches.
pub fn apply_signal(gravastar_bin: &str, signal: &LedSignal) -> i32 {
    match signal {
        LedSignal::PulsingRed => run_inherit(
            gravastar_bin,
            &["breathe", "red", "--speed", "7", "--brightness", "9"],
        ),
        LedSignal::SolidRed => run_inherit(gravastar_bin, &["color", "red", "--brightness", "7"]),
        LedSignal::PulsingYellow => run_inherit(
            gravastar_bin,
            &["breathe", "yellow", "--speed", "5", "--brightness", "7"],
        ),
        LedSignal::SolidGreen => run_inherit(gravastar_bin, &["signal", "success"]),
        LedSignal::Warning => run_inherit(gravastar_bin, &["signal", "warning"]),
    }
}

/// Resolve GRAVASTAR_BIN, matching the shell's resolution chain:
/// env → on_path → runfiles → bazel-bin → build.
pub fn resolve_gravastar_bin() -> String {
    if let Ok(bin) = std::env::var("GRAVASTAR_BIN") {
        if !bin.is_empty() {
            return bin;
        }
    }
    if sh::on_path("gravastar-mouse") {
        return "gravastar-mouse".to_string();
    }
    if let Some(bin) = find_in_runfiles() {
        return bin;
    }
    let workspace = workspace_dir();
    let bazel_bin_path = format!("{workspace}/bazel-bin/packages/peripherals/gravastar-mouse");
    if std::path::Path::new(&bazel_bin_path)
        .metadata()
        .map_or(false, |m| m.is_file())
    {
        return bazel_bin_path;
    }
    sh::out_line("Building //packages/peripherals:gravastar-mouse...\n");
    run_inherit(
        "bazel",
        &[
            "build",
            "--config=macos-app",
            "//packages/peripherals:gravastar-mouse",
        ],
    );
    bazel_bin_path
}

fn workspace_dir() -> String {
    match std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        Ok(dir) if !dir.is_empty() => dir,
        _ => {
            let cap = sh::capture("git", &["rev-parse", "--show-toplevel"]);
            if cap.status == 0 && !cap.out.is_empty() {
                cap.out
            } else {
                ".".to_string()
            }
        }
    }
}

fn find_in_runfiles() -> Option<String> {
    let runfiles = std::env::var("RUNFILES_DIR").ok()?;
    if runfiles.is_empty() {
        return None;
    }
    for ws in &["vitruvian_core", "_main"] {
        let path = format!("{runfiles}/{ws}/packages/peripherals/gravastar-mouse");
        if std::path::Path::new(&path)
            .metadata()
            .map_or(false, |m| m.is_file())
        {
            return Some(path);
        }
    }
    None
}

fn resolve_sha(repo: &str, branch: &str) -> String {
    let sha = sh::capture(
        "gh",
        &[
            "api",
            &format!("repos/{repo}/commits/{branch}"),
            "--jq",
            ".sha",
        ],
    );
    if sha.status == 0 && !sha.out.is_empty() {
        return sha.out;
    }
    let sha = sh::capture("git", &["rev-parse", &format!("origin/{branch}")]);
    if sha.status == 0 && !sha.out.is_empty() {
        return sha.out;
    }
    "HEAD".to_string()
}

fn poll_external(repo: &str, sha: &str, cmd: &str) -> PollResult {
    let _ = std::io::stdout().flush();
    let output = Command::new(cmd)
        .arg(sha)
        .env("PIPELINE_REPO", repo)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output();

    match output {
        Ok(out) => {
            let rc = sh::status_code(out.status);
            let stdout = String::from_utf8_lossy(&out.stdout);
            let stderr = String::from_utf8_lossy(&out.stderr);
            let combined = format!("{stdout}{stderr}");
            let _ = std::fs::write(STATUS_OUT_PATH, combined.as_bytes());
            let failed_count = parse_count(&combined, "failed");
            let in_flight_count = parse_count(&combined, "in-flight");
            let summary = combined.lines().nth(1).unwrap_or("").to_string();
            PollResult {
                rc,
                failed_count,
                in_flight_count,
                summary,
            }
        }
        Err(_) => PollResult {
            rc: 127,
            failed_count: 0,
            in_flight_count: 0,
            summary: String::new(),
        },
    }
}

fn poll_internal(repo: &str, sha: &str) -> PollResult {
    let short = sh::prefix(sha, 8);
    let runs_json = sh::capture_or_echo(
        "gh",
        &[
            "api",
            &format!("repos/{repo}/actions/runs?head_sha={sha}&per_page=100"),
        ],
        NO_RUNS_JSON,
    );
    let evaluation = evaluate_runs_json(&runs_json);
    let eval_output = sh::subst_text(evaluation.stdout.as_bytes());
    let failed_count = parse_count(&eval_output, "failed");
    let in_flight_count = parse_count(&eval_output, "in-flight");

    let summary = match evaluation.status {
        0 => format!(
            "\x1b[32m\u{2713}\x1b[0m All post-merge workflows for {short} are GREEN ({eval_output})"
        ),
        1 => format!(
            "\x1b[31m\u{2717}\x1b[0m Pipeline FAILED for commit {short} ({eval_output})"
        ),
        2 => format!(
            "\x1b[33m\u{231b}\x1b[0m Pipeline is currently IN PROGRESS for commit {short} ({eval_output})"
        ),
        _ => format!(
            "\x1b[33m\u{231b}\x1b[0m No workflow runs found yet for commit {short}"
        ),
    };

    let info_line = format!(
        "\x1b[36m\u{2192}\x1b[0m Checking GitHub Actions pipeline status for commit {short} in {repo}...\n"
    );
    let full_output = format!("{info_line}{summary}\n");
    let _ = std::fs::write(STATUS_OUT_PATH, full_output.as_bytes());

    PollResult {
        rc: evaluation.status,
        failed_count,
        in_flight_count,
        summary,
    }
}

fn poll(config: &DaemonConfig, sha: &str) -> PollResult {
    match &config.pipeline_cmd {
        Some(cmd) => poll_external(&config.repo, sha, cmd),
        None => poll_internal(&config.repo, sha),
    }
}

fn print_banner(config: &DaemonConfig) {
    let mut out = std::io::stdout().lock();
    let _ = writeln!(out, "=== GravaStar Main Branch CI Status Daemon ===");
    let _ = writeln!(out, "Repo:     {}", config.repo);
    let _ = writeln!(out, "Branch:   {}", config.branch);
    let _ = writeln!(out, "Interval: {}s", config.interval);
    let _ = writeln!(out, "Mouse:    {}", config.gravastar_bin);
    let _ = writeln!(out, "LED Matrix:");
    let _ = writeln!(
        out,
        "  \u{2022} Pulsing Yellow: in-progress (no failures so far)"
    );
    let _ = writeln!(
        out,
        "  \u{2022} Pulsing Red:    early failure (failed check, more still running)"
    );
    let _ = writeln!(
        out,
        "  \u{2022} Solid Red:      pipeline completed with failure"
    );
    let _ = writeln!(
        out,
        "  \u{2022} Solid Green:    pipeline completed with all green"
    );
    let _ = writeln!(out, "Press Ctrl+C to stop and restore baseline lighting.");
    let _ = writeln!(out);
    let _ = out.flush();
}

fn timestamp() -> String {
    let ts = sh::capture("date", &["+%H:%M:%S"]);
    if ts.status == 0 && !ts.out.is_empty() {
        ts.out
    } else {
        "??:??:??".to_string()
    }
}

fn cleanup(gravastar_bin: &str) {
    let mut out = std::io::stdout().lock();
    let _ = writeln!(out);
    let _ = writeln!(
        out,
        "Stopping daemon. Restoring original mouse lighting baseline..."
    );
    let _ = out.flush();
    let _ = Command::new(gravastar_bin).arg("restore").status();
}

fn install_signal_handlers() {
    unsafe {
        signal(2, handle_signal); // SIGINT
        signal(15, handle_signal); // SIGTERM
    }
}

/// Run the daemon loop.  Returns the exit code.
pub fn run(config: &DaemonConfig) -> i32 {
    INTERRUPTED.store(false, Ordering::SeqCst);
    install_signal_handlers();
    print_banner(config);

    let mut last_signal: Option<String> = None;
    let mut last_sha = String::new();
    let mut iterations: u64 = 0;

    loop {
        if INTERRUPTED.load(Ordering::SeqCst) {
            cleanup(&config.gravastar_bin);
            return 0;
        }

        let target_sha = resolve_sha(&config.repo, &config.branch);
        let result = poll(config, &target_sha);
        let led = determine_signal(result.rc, result.failed_count, result.in_flight_count);
        let signal_name = led.name();
        let short = sh::prefix(&target_sha, 8);
        let ts = timestamp();

        let last_name = last_signal.as_deref().unwrap_or("none");
        if signal_name != last_name || target_sha != last_sha {
            let mut out = std::io::stdout().lock();
            let _ = writeln!(
                out,
                "[{ts}] Commit: {short} | Status transition: '{last_name}' -> '{signal_name}'"
            );
            let _ = writeln!(out, "  {}", result.summary);
            let _ = out.flush();
            apply_signal(&config.gravastar_bin, &led);
            last_signal = Some(signal_name.to_string());
            last_sha = target_sha;
        } else {
            sh::out_line(&format!(
                "[{ts}] Commit: {short} | Status steady: {signal_name}\n"
            ));
        }

        iterations += 1;
        if config.once {
            return 0;
        }
        if let Some(max) = config.max_iterations {
            if iterations >= max {
                return 0;
            }
        }

        let total_ms = config.interval * 1000;
        let mut slept = 0u64;
        while slept < total_ms {
            if INTERRUPTED.load(Ordering::SeqCst) {
                cleanup(&config.gravastar_bin);
                return 0;
            }
            let chunk = (total_ms - slept).min(200);
            std::thread::sleep(std::time::Duration::from_millis(chunk));
            slept += chunk;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn led_signal_names() {
        assert_eq!(LedSignal::PulsingRed.name(), "pulsing_red");
        assert_eq!(LedSignal::SolidRed.name(), "solid_red");
        assert_eq!(LedSignal::PulsingYellow.name(), "pulsing_yellow");
        assert_eq!(LedSignal::SolidGreen.name(), "solid_green");
        assert_eq!(LedSignal::Warning.name(), "warning");
    }

    #[test]
    fn determine_signal_matrix() {
        assert_eq!(determine_signal(1, 1, 1), LedSignal::PulsingRed);
        assert_eq!(determine_signal(1, 2, 3), LedSignal::PulsingRed);

        assert_eq!(determine_signal(1, 1, 0), LedSignal::SolidRed);
        assert_eq!(determine_signal(1, 3, 0), LedSignal::SolidRed);

        assert_eq!(determine_signal(2, 0, 1), LedSignal::PulsingYellow);
        assert_eq!(determine_signal(2, 0, 5), LedSignal::PulsingYellow);

        assert_eq!(determine_signal(0, 0, 0), LedSignal::SolidGreen);

        assert_eq!(determine_signal(3, 0, 0), LedSignal::Warning);
        assert_eq!(determine_signal(127, 0, 0), LedSignal::Warning);
    }

    #[test]
    fn parse_count_from_evaluation_output() {
        assert_eq!(
            parse_count(
                "FAILED: 1 failed, 1 in-flight, 0 passed out of 2 total",
                "failed"
            ),
            1
        );
        assert_eq!(
            parse_count(
                "FAILED: 1 failed, 1 in-flight, 0 passed out of 2 total",
                "in-flight"
            ),
            1
        );
        assert_eq!(
            parse_count(
                "IN_PROGRESS: 2 in-flight, 3 passed out of 5 total",
                "in-flight"
            ),
            2
        );
        assert_eq!(
            parse_count(
                "IN_PROGRESS: 2 in-flight, 3 passed out of 5 total",
                "failed"
            ),
            0
        );
        assert_eq!(
            parse_count("ALL_PASSED: 5 passed out of 5 total", "failed"),
            0
        );
        assert_eq!(parse_count("NO_RUNS", "failed"), 0);
        assert_eq!(parse_count("", "failed"), 0);
    }

    #[test]
    fn parse_count_with_ansi_codes() {
        let output = "\x1b[31m\u{2717}\x1b[0m Pipeline FAILED for commit abc12345 (FAILED: 2 failed, 1 in-flight, 0 passed out of 3 total)";
        assert_eq!(parse_count(output, "failed"), 2);
        assert_eq!(parse_count(output, "in-flight"), 1);
    }

    #[test]
    fn parse_count_multiline() {
        let output = "line one no counts\nFAILED: 3 failed, 2 in-flight, 1 passed out of 6 total\n";
        assert_eq!(parse_count(output, "failed"), 3);
        assert_eq!(parse_count(output, "in-flight"), 2);
    }
}
