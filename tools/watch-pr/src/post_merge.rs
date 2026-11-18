// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

//! What watch-pr does after one pipeline-status poll of the squash commit.
//! Kept apart from the poll loop so the rule can be tested.

/// Seconds after landing that "no runs yet" is expected, and reported as such.
pub const POST_MERGE_GRACE: i64 = 60;

#[derive(Debug, PartialEq, Eq)]
pub enum Decision {
    /// Every push workflow finished green: report success.
    Green,
    /// A push workflow failed.
    Failed,
    /// Runs exist and are not all done (or are still settling): poll again.
    InProgress,
    /// No push runs yet, inside the grace period: poll again.
    AwaitRegistration,
    /// No push runs after the grace period: still not a pass; poll again until
    /// the watchdog deadline turns this into a timeout.
    NoRunsStillWaiting,
    /// A return code pipeline-status does not define: retry.
    Unexpected(i32),
    /// pipeline-status never ran: Bazel could not build or launch it (a
    /// broken local cache, a crashed server). Its exit code says nothing
    /// about CI, so retry, and after `TOOL_ERROR_RETRIES` in a row give up
    /// with `EXIT_TOOL_ERROR`, never `EXIT_FAILED`.
    ToolError,
}

/// watch-pr's exit codes for the post-merge phase.
pub const EXIT_GREEN: i32 = 0;
pub const EXIT_FAILED: i32 = 1;
pub const EXIT_TIMEOUT: i32 = 2;
/// pipeline-status itself could not be built or run, so the pipeline's state
/// is unknown. Distinct from `EXIT_FAILED`: CI did not fail.
pub const EXIT_TOOL_ERROR: i32 = 4;

/// Consecutive polls where pipeline-status could not run before watch-pr
/// gives up. A transient Bazel hiccup clears in one; a broken cache does not.
pub const TOOL_ERROR_RETRIES: u32 = 3;

/// Lines Bazel prints when it fails before running the target. Bazel exits 1
/// for a failed build (2 for a bad command line), which pipeline-status uses
/// for "red" (and "in flight"), so only these lines tell the two apart.
const BAZEL_FAILURE_MARKERS: &[&str] = &[
    "Build did NOT complete successfully",
    "Build failed. Not running target",
    "Server terminated abruptly",
];

impl Decision {
    /// The exit code that ends the watch, or `None` to keep polling. Only
    /// `Green` exits 0; the deadline (not a `Decision`) exits `EXIT_TIMEOUT`.
    pub fn exit_code(&self) -> Option<i32> {
        match self {
            Decision::Green => Some(EXIT_GREEN),
            Decision::Failed => Some(EXIT_FAILED),
            _ => None,
        }
    }
}

/// Map pipeline-status' exit code (0 green, 1 red, 2 in flight, 3 no runs)
/// and the seconds since landing to the next step. Only `0` is ever `Green`;
/// zero runs, however long, is never a pass.
pub fn decide(rc: i32, secs_since_landing: i64) -> Decision {
    match rc {
        0 => Decision::Green,
        1 => Decision::Failed,
        2 => Decision::InProgress,
        3 if secs_since_landing < POST_MERGE_GRACE => Decision::AwaitRegistration,
        3 => Decision::NoRunsStillWaiting,
        other => Decision::Unexpected(other),
    }
}

/// `decide`, but first ask whether pipeline-status ran at all: when its
/// output shows Bazel failed to build or launch it, the exit code is Bazel's,
/// not pipeline-status', and is never read as a verdict.
pub fn judge(rc: i32, secs_since_landing: i64, report: &Report) -> Decision {
    if rc != 0 && report.tool_failure.is_some() {
        return Decision::ToolError;
    }
    decide(rc, secs_since_landing)
}

/// Counts `ToolError` polls in a row; any other decision resets it.
#[derive(Debug, Default)]
pub struct ToolErrors {
    pub consecutive: u32,
}

impl ToolErrors {
    /// Record one poll's decision. Returns `Some(EXIT_TOOL_ERROR)` once
    /// pipeline-status has failed to run `TOOL_ERROR_RETRIES` times in a row.
    pub fn record(&mut self, decision: &Decision) -> Option<i32> {
        if *decision == Decision::ToolError {
            self.consecutive += 1;
            (self.consecutive >= TOOL_ERROR_RETRIES).then_some(EXIT_TOOL_ERROR)
        } else {
            self.consecutive = 0;
            None
        }
    }
}

/// What watch-pr reads from one pipeline-status run's output, beyond its
/// exit code.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Report {
    /// pipeline-status' note that the commit was judged by the tip of the
    /// batched push that landed it.
    pub batched: Option<String>,
    /// Why pipeline-status gave no verdict, when it said so. Its exit code is
    /// 3 both for this and for a push with no runs, so only the text tells
    /// them apart.
    pub no_verdict: Option<String>,
    /// The no-verdict reason is a failed GitHub call.
    pub read_failed: bool,
    /// Bazel failed to build or launch pipeline-status: its first `ERROR:`
    /// line (or the failure line itself when there is none).
    pub tool_failure: Option<String>,
}

/// Read pipeline-status' output (stdout and stderr merged, colours and all).
pub fn read_report(out: &str) -> Report {
    let mut report = Report::default();
    let mut first_error: Option<String> = None;
    let mut bazel_failed: Option<String> = None;
    for line in out.lines() {
        if first_error.is_none() {
            if let Some(i) = line.find("ERROR: ") {
                first_error = Some(line[i..].trim_end().to_string());
            }
        }
        if bazel_failed.is_none() && BAZEL_FAILURE_MARKERS.iter().any(|m| line.contains(m)) {
            bazel_failed = Some(line.trim().to_string());
        }
        if let Some(i) = line.find("batched: ") {
            report.batched = Some(line[i..].trim_end().to_string());
        }
        if let Some(i) = line.find("No verdict yet for commit ") {
            let rest = &line[i + "No verdict yet for commit ".len()..];
            // "<short>: <why>"
            let why = rest.split_once(": ").map_or(rest, |(_, why)| why);
            report.read_failed = why.contains(" failed (exit ");
            report.no_verdict = Some(why.trim_end().to_string());
        }
    }
    if bazel_failed.is_some() {
        report.tool_failure = first_error.or(bazel_failed);
    }
    report
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The lines pipeline-status printed for PR #4953 (fa49ec5e, tip 5373aea8).
    #[test]
    fn reads_the_batched_note_and_the_no_verdict_reason() {
        let green = "\x1b[36m→\x1b[0m batched: fa49ec5e landed in a push whose tip is 5373aea8; evaluating the tip's runs\n\x1b[32m✓\x1b[0m All post-merge workflows for fa49ec5e are GREEN (ALL_PASSED: 20 passed out of 20 total)\n";
        let r = read_report(green);
        assert_eq!(
            r.batched.as_deref(),
            Some("batched: fa49ec5e landed in a push whose tip is 5373aea8; evaluating the tip's runs")
        );
        assert_eq!(r.no_verdict, None);

        let expired = "\x1b[33m⚠\x1b[0m No verdict yet for commit fa49ec5e: cannot read the push history: gh api repos/o/r/activity?ref=refs/heads/main&per_page=100 failed (exit 1)\n";
        let r = read_report(expired);
        assert!(r.read_failed);
        assert!(r
            .no_verdict
            .as_deref()
            .unwrap()
            .starts_with("cannot read the push history: gh api"));

        let unknown = "No verdict yet for commit feedface: commit feedface has no push runs and is not in the 15 newest pushes to main\n";
        let r = read_report(unknown);
        assert!(!r.read_failed);
        assert!(r
            .no_verdict
            .unwrap()
            .contains("not in the 15 newest pushes"));

        assert_eq!(
            read_report("No workflow runs found yet for commit abc\n"),
            Report::default()
        );
    }

    /// What `bazel run //tools/pipeline-status` printed on 2026-11-18 when the
    /// worktree's output base had lost `external/rules_python+` (PR #5110):
    /// Bazel exited 1, and watch-pr called the green pipeline FAILED.
    const BROKEN_CACHE: &str = "\x1b[32mINFO: \x1b[0mInvocation ID: 0b1e\n\x1b[31m\x1b[1mERROR: \x1b[0m/private/var/tmp/_bazel_james/abc/external/rules_python+/python/private/BUILD.bazel: no such package '@@rules_python+//python/private': BUILD file not found\n\x1b[31m\x1b[1mERROR: \x1b[0mAnalysis of target '//tools/pipeline-status:pipeline-status' failed; build aborted\n\x1b[32mINFO: \x1b[0mElapsed time: 0.412s\n\x1b[31m\x1b[1mFAILED:\x1b[0m Build did NOT complete successfully (0 packages loaded)\n\x1b[31m\x1b[1mERROR: \x1b[0mBuild failed. Not running target\n";

    #[test]
    fn a_bazel_build_failure_is_a_tool_error_not_a_red_pipeline() {
        let r = read_report(BROKEN_CACHE);
        let why = r.tool_failure.as_deref().expect("build failure recognised");
        assert!(why.starts_with("ERROR: "), "{why}");
        assert!(why.contains("rules_python+"), "{why}");

        // Bazel's own exit 1 (failed build) and 2 (bad command line) are
        // neither "red" nor "in flight".
        for rc in [1, 2, 3, 36] {
            assert_eq!(judge(rc, 600, &r), Decision::ToolError, "rc {rc}");
            assert_eq!(judge(rc, 600, &r).exit_code(), None, "rc {rc}");
        }
        // The failure line alone is enough when no ERROR: line came first.
        let bare = read_report("FAILED: Build did NOT complete successfully\n");
        assert_eq!(
            bare.tool_failure.as_deref(),
            Some("FAILED: Build did NOT complete successfully")
        );
        assert_eq!(judge(1, 0, &bare), Decision::ToolError);
    }

    #[test]
    fn pipeline_status_own_exit_one_is_still_failed() {
        let red = "\x1b[32mINFO: \x1b[0mRunning command line: bazel-bin/tools/pipeline-status/pipeline-status 565eb3c0\n\x1b[31m✗\x1b[0m Post-merge workflows for 565eb3c0 FAILED (1 failed out of 23 total)\n";
        let r = read_report(red);
        assert_eq!(r.tool_failure, None);
        assert_eq!(judge(1, 600, &r), Decision::Failed);
        assert_eq!(judge(1, 600, &r).exit_code(), Some(EXIT_FAILED));
        // A workflow that printed ERROR: in its name is not a Bazel failure.
        let named = read_report("✗ ERROR: lint job failed\n");
        assert_eq!(named.tool_failure, None);
        assert_eq!(judge(1, 0, &named), Decision::Failed);
        // A green run that happened to log a Bazel-looking line is still green.
        assert_eq!(judge(0, 0, &read_report(BROKEN_CACHE)), Decision::Green);
    }

    #[test]
    fn tool_errors_give_up_with_their_own_code_after_retries() {
        let mut t = ToolErrors::default();
        for _ in 1..TOOL_ERROR_RETRIES {
            assert_eq!(t.record(&Decision::ToolError), None);
        }
        // Any real answer in between resets the count.
        assert_eq!(t.record(&Decision::InProgress), None);
        for _ in 1..TOOL_ERROR_RETRIES {
            assert_eq!(t.record(&Decision::ToolError), None);
        }
        assert_eq!(t.record(&Decision::ToolError), Some(EXIT_TOOL_ERROR));
        assert_ne!(EXIT_TOOL_ERROR, EXIT_FAILED);
        assert_ne!(EXIT_TOOL_ERROR, EXIT_TIMEOUT);
        assert_ne!(EXIT_TOOL_ERROR, 3, "3 is a bad argument");
    }

    #[test]
    fn zero_runs_is_never_green_however_long_we_wait() {
        for secs in [0, 59, 60, 61, 600, 86_400] {
            assert_ne!(decide(3, secs), Decision::Green, "{secs}s");
        }
        assert_eq!(decide(3, 10), Decision::AwaitRegistration);
        assert_eq!(decide(3, 60), Decision::NoRunsStillWaiting);
    }

    #[test]
    fn only_exit_zero_is_green() {
        assert_eq!(decide(0, 0), Decision::Green);
        for rc in [1, 2, 3, 4, 255, -1] {
            assert_ne!(decide(rc, 1000), Decision::Green, "rc {rc}");
        }
        assert_eq!(decide(1, 0), Decision::Failed);
        assert_eq!(decide(2, 0), Decision::InProgress);
        assert_eq!(decide(9, 0), Decision::Unexpected(9));
    }

    #[test]
    fn exit_codes_end_the_watch_only_on_green_or_red() {
        assert_eq!(decide(0, 0).exit_code(), Some(0));
        assert_eq!(decide(1, 0).exit_code(), Some(1));
        for (rc, secs) in [(2, 0), (3, 0), (3, 10_000), (7, 0)] {
            assert_eq!(decide(rc, secs).exit_code(), None, "rc {rc}");
        }
        assert_eq!(EXIT_TIMEOUT, 2);
    }
}
