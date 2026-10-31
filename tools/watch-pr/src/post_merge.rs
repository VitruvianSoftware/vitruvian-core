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

#[cfg(test)]
mod tests {
    use super::*;

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
}
