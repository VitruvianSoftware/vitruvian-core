// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

//! Batched merges. The merge queue can land several pull requests in one push
//! to main, and GitHub starts the push workflows for the tip commit of that
//! push only: the earlier squash commits have no push runs at all (PR 4090,
//! 7f179efe, ran nothing; the tip 11e146c1 ran 42). Asking for the PR's own
//! squash SHA would then wait for runs that never come.

use crate::evaluate::{assess, Evaluation};

/// How many commits after the squash commit to look through for the tip.
pub const MAX_WALK: usize = 20;

pub struct Commit {
    pub sha: String,
    pub subject: String,
}

pub struct Resolved {
    pub evaluation: Evaluation,
    /// The push-only runs listing the verdict is based on.
    pub runs_json: String,
    /// The commit whose runs were evaluated (the squash commit or the tip).
    pub sha: String,
    /// "batched with #N; evaluating tip <sha>" when a later commit was used.
    pub note: Option<String>,
}

/// The `(#N)` GitHub appends to a squash subject.
pub fn pr_number(subject: &str) -> Option<String> {
    let end = subject.rfind(')')?;
    let start = subject[..end].rfind("(#")?;
    let digits = &subject[start + 2..end];
    (!digits.is_empty() && digits.bytes().all(|b| b.is_ascii_digit())).then(|| digits.to_string())
}

/// Evaluate `sha`'s push runs; when it has none and the settle window has
/// passed, look through the commits after it (oldest first, at most
/// `MAX_WALK`) for the first one that does: the tip of the push that landed
/// it. Zero runs anywhere stays "no runs" (status 3), never green.
///
/// `commit_epoch` is when `sha` was committed: inside the settle window its own
/// runs may simply not have registered, and a later commit's runs would be
/// someone else's.
pub fn resolve(
    sha: &str,
    branch: &str,
    commit_epoch: i64,
    now: i64,
    settle: i64,
    runs_for: &dyn Fn(&str) -> String,
    later_commits: &dyn Fn() -> Vec<Commit>,
) -> Resolved {
    let (evaluation, runs_json) = assess(&runs_for(sha), sha, branch, now, settle);
    let own = Resolved {
        evaluation,
        runs_json,
        sha: sha.to_string(),
        note: None,
    };
    if own.evaluation.status != 3 || now - commit_epoch < settle {
        return own;
    }
    for c in later_commits().into_iter().take(MAX_WALK) {
        let (evaluation, runs_json) = assess(&runs_for(&c.sha), &c.sha, branch, now, settle);
        if evaluation.status != 3 {
            let short: String = c.sha.chars().take(8).collect();
            let with = pr_number(&c.subject)
                .map(|n| format!(" with #{n}"))
                .unwrap_or_default();
            return Resolved {
                evaluation,
                runs_json,
                note: Some(format!("batched{with}; evaluating tip {short}")),
                sha: c.sha,
            };
        }
    }
    own
}

#[cfg(test)]
mod tests {
    use super::*;

    const SQUASH: &str = "7f179efe0000000000000000000000000000aaaa";
    const TIP: &str = "11e146c10000000000000000000000000000bbbb";
    const LATER: &str = "2a80e85b0000000000000000000000000000cccc";
    // 2026-10-31T06:58:34Z and the time pipeline-status ran, an hour on.
    const T: i64 = 1793429914;
    const NOW: i64 = T + 3600;

    fn push_run(sha: &str, status: &str, concl: &str) -> String {
        let c = if concl.is_empty() {
            "null".to_string()
        } else {
            format!("\"{concl}\"")
        };
        format!(
            r#"{{"id":1,"workflow_id":1,"name":"CI","event":"push","head_branch":"main","head_sha":"{sha}","status":"{status}","conclusion":{c},"created_at":"2026-10-31T06:58:34Z"}}"#
        )
    }

    /// The API as it was for the 4090/4091 batch: the squash SHA has no push
    /// runs, the tip has them.
    fn api(tip_status: &'static str, tip_concl: &'static str) -> impl Fn(&str) -> String {
        move |sha: &str| {
            if sha == TIP {
                format!(
                    r#"{{"workflow_runs":[{}]}}"#,
                    push_run(TIP, tip_status, tip_concl)
                )
            } else {
                r#"{"total_count":0,"workflow_runs":[]}"#.to_string()
            }
        }
    }

    fn after() -> Vec<Commit> {
        vec![
            Commit {
                sha: TIP.into(),
                subject: "refactor(peripherals): publish gravastar-mouse from Rust (#4091)".into(),
            },
            Commit {
                sha: LATER.into(),
                subject: "fix(ci): other (#4095)".into(),
            },
        ]
    }

    #[test]
    fn pr_numbers_come_from_the_trailing_marker() {
        assert_eq!(pr_number("fix: a (#12) (#4091)"), Some("4091".into()));
        assert_eq!(pr_number("fix: no marker"), None);
        assert_eq!(pr_number("fix: (#) odd"), None);
    }

    /// Fail-before: without the walk this is status 3 forever, which
    /// watch-pr turns into a timeout (exit 2) for a PR that landed fine.
    #[test]
    fn a_batched_non_tip_commit_is_judged_by_the_tip() {
        let r = resolve(
            SQUASH,
            "main",
            T,
            NOW,
            60,
            &api("completed", "success"),
            &after,
        );
        assert_eq!(r.evaluation.status, 0, "{}", r.evaluation.stdout);
        assert_eq!(r.sha, TIP);
        assert_eq!(
            r.note.as_deref(),
            Some("batched with #4091; evaluating tip 11e146c1")
        );
    }

    #[test]
    fn the_tips_failure_and_in_flight_state_carry_over() {
        let r = resolve(
            SQUASH,
            "main",
            T,
            NOW,
            60,
            &api("completed", "failure"),
            &after,
        );
        assert_eq!(r.evaluation.status, 1);
        let r = resolve(SQUASH, "main", T, NOW, 60, &api("in_progress", ""), &after);
        assert_eq!(r.evaluation.status, 2);
    }

    #[test]
    fn never_green_on_zero_runs_anywhere() {
        let none = |_: &str| r#"{"workflow_runs":[]}"#.to_string();
        let r = resolve(SQUASH, "main", T, NOW, 60, &none, &after);
        assert_eq!(r.evaluation.status, 3);
        assert!(r.note.is_none());
        let nothing_later = || Vec::new();
        let r = resolve(
            SQUASH,
            "main",
            T,
            NOW,
            60,
            &api("completed", "success"),
            &nothing_later,
        );
        assert_eq!(r.evaluation.status, 3);
    }

    #[test]
    fn inside_the_settle_window_the_commit_is_not_given_a_later_commits_runs() {
        let r = resolve(
            SQUASH,
            "main",
            NOW - 10,
            NOW,
            60,
            &api("completed", "success"),
            &after,
        );
        assert_eq!(r.evaluation.status, 3);
        assert!(r.note.is_none());
    }

    #[test]
    fn a_commit_with_its_own_runs_never_walks() {
        let own = |sha: &str| {
            format!(
                r#"{{"workflow_runs":[{}]}}"#,
                push_run(sha, "completed", "success")
            )
        };
        let r = resolve(SQUASH, "main", T, NOW, 60, &own, &after);
        assert_eq!((r.evaluation.status, r.sha.as_str()), (0, SQUASH));
        assert!(r.note.is_none());
    }

    #[test]
    fn the_walk_is_bounded() {
        let far: Vec<Commit> = (0..MAX_WALK + 5)
            .map(|i| Commit {
                sha: if i == MAX_WALK + 2 {
                    TIP.into()
                } else {
                    format!("{i:040}")
                },
                subject: "x".into(),
            })
            .collect();
        let r = resolve(
            SQUASH,
            "main",
            T,
            NOW,
            60,
            &api("completed", "success"),
            &|| {
                far.iter()
                    .map(|c| Commit {
                        sha: c.sha.clone(),
                        subject: c.subject.clone(),
                    })
                    .collect()
            },
        );
        assert_eq!(r.evaluation.status, 3);
    }
}
