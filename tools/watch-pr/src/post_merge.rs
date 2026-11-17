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
}

/// watch-pr's exit codes for the post-merge phase.
pub const EXIT_GREEN: i32 = 0;
pub const EXIT_FAILED: i32 = 1;
pub const EXIT_TIMEOUT: i32 = 2;

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
}

/// Read pipeline-status' output (stdout and stderr merged, colours and all).
pub fn read_report(out: &str) -> Report {
    let mut report = Report::default();
    for line in out.lines() {
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
