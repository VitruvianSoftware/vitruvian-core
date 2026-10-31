// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

//! Batched merges. The merge queue can land several pull requests in one push
//! to main, and GitHub starts the push workflows for the tip commit of that
//! push only: the earlier squash commits have no push runs at all (PR 4090,
//! 7f179efe, ran nothing; the tip 11e146c1 ran 42). Asking for the PR's own
//! squash SHA would then wait for runs that never come.
//!
//! The push is found from GitHub's repository activity API, which records
//! `before`, `after` and a timestamp for every push to a branch. The push whose
//! range holds the squash commit is the one that landed it; its `after` commit
//! is the tip whose runs count. Nothing here guesses: if the push cannot be
//! found, or any call fails, the answer is "waiting", never a verdict, and an
//! API failure is never read as "zero runs".

use crate::evaluate::{assess, parse_utc, Evaluation};

/// How many of the newest pushes to search for the one holding the commit.
pub const MAX_PUSHES: usize = 15;

#[derive(Debug, PartialEq, Clone)]
pub struct Push {
    pub before: String,
    pub after: String,
    pub timestamp: String,
}

pub struct Resolved {
    pub evaluation: Evaluation,
    /// The push-only runs listing the verdict is based on.
    pub runs_json: String,
    /// The commit whose runs were evaluated (the push's tip).
    pub sha: String,
    /// Set when the tip is a different commit than the one asked about.
    pub note: Option<String>,
}

pub enum Outcome {
    Judged(Resolved),
    /// No verdict yet, and why. Never green; the caller keeps waiting.
    Waiting(String),
}

/// The pushes in an activity response, newest first as GitHub sends them. A
/// body that is not a list of pushes (an error object, junk) is an error.
pub fn parse_activity(json: &str) -> Result<Vec<Push>, String> {
    let doc: serde_json::Value =
        serde_json::from_str(json).map_err(|e| format!("activity response is not JSON: {e}"))?;
    let items = doc
        .as_array()
        .ok_or_else(|| "activity response is not a list".to_string())?;
    let field =
        |v: &serde_json::Value, k: &str| v.get(k).and_then(|x| x.as_str()).map(String::from);
    items
        .iter()
        .map(|v| {
            Ok(Push {
                before: field(v, "before").ok_or("activity entry without before")?,
                after: field(v, "after").ok_or("activity entry without after")?,
                timestamp: field(v, "timestamp").ok_or("activity entry without timestamp")?,
            })
        })
        .collect()
}

/// The commit SHAs a compare response holds. Errors when the response is not a
/// compare, or lists fewer commits than the range has.
pub fn parse_range(json: &str) -> Result<Vec<String>, String> {
    let doc: serde_json::Value =
        serde_json::from_str(json).map_err(|e| format!("compare response is not JSON: {e}"))?;
    let commits = doc
        .get("commits")
        .and_then(|c| c.as_array())
        .ok_or_else(|| "compare response has no commits list".to_string())?;
    let total = doc
        .get("total_commits")
        .and_then(|t| t.as_u64())
        .unwrap_or(commits.len() as u64);
    if total as usize > commits.len() {
        return Err(format!(
            "range has {total} commits, only {} listed",
            commits.len()
        ));
    }
    Ok(commits
        .iter()
        .filter_map(|c| c.get("sha").and_then(|s| s.as_str()).map(String::from))
        .collect())
}

/// A runs listing is usable only if GitHub answered with one: an error body
/// (`{"message": ...}`) parses fine and would otherwise read as no runs.
pub fn check_runs_response(json: &str) -> Result<(), String> {
    let doc: serde_json::Value =
        serde_json::from_str(json).map_err(|e| format!("runs response is not JSON: {e}"))?;
    match doc.get("workflow_runs") {
        Some(r) if r.is_array() => Ok(()),
        _ => Err("runs response has no workflow_runs list".to_string()),
    }
}

/// Judge the push that landed `sha`.
///
/// `activity` fetches the activity listing, `range(before, after)` the
/// commits of a push, `runs_for(commit)` the runs listing; each reports a
/// failed call as `Err`. Settle is measured from the push's own timestamp, on
/// top of the settle already applied to the tip's earliest run.
pub fn resolve(
    sha: &str,
    branch: &str,
    now: i64,
    settle: i64,
    activity: &dyn Fn() -> Result<String, String>,
    range: &dyn Fn(&str, &str) -> Result<String, String>,
    runs_for: &dyn Fn(&str) -> Result<String, String>,
) -> Outcome {
    let pushes = match activity().and_then(|j| parse_activity(&j)) {
        Ok(p) => p,
        Err(e) => return Outcome::Waiting(format!("cannot read the push history: {e}")),
    };
    let mut found: Option<Push> = None;
    for push in pushes.into_iter().take(MAX_PUSHES) {
        if push.after == sha {
            found = Some(push);
            break;
        }
        let shas = match range(&push.before, &push.after).and_then(|j| parse_range(&j)) {
            Ok(s) => s,
            Err(e) => return Outcome::Waiting(format!("cannot read a push's commits: {e}")),
        };
        if shas.iter().any(|s| s == sha) {
            found = Some(push);
            break;
        }
    }
    let Some(push) = found else {
        return Outcome::Waiting(format!(
            "commit {} is not in the {MAX_PUSHES} newest pushes to {branch} yet",
            sha.chars().take(8).collect::<String>()
        ));
    };
    let tip = push.after.clone();
    let raw = match runs_for(&tip).and_then(|j| check_runs_response(&j).map(|_| j)) {
        Ok(j) => j,
        Err(e) => return Outcome::Waiting(format!("cannot read the tip's runs: {e}")),
    };
    let (mut evaluation, runs_json) = assess(&raw, &tip, branch, now, settle);
    if evaluation.status == 0 {
        if let Some(t) = parse_utc(&push.timestamp) {
            let left = settle - (now - t);
            if left > 0 {
                evaluation.stdout = format!(
                    "settling: {left}s left before green; {} (the push landed {}s ago)\n",
                    evaluation.stdout.trim_end(),
                    now - t
                );
                evaluation.status = 2;
            }
        }
    }
    let note = (tip != sha).then(|| {
        let short: String = tip.chars().take(8).collect();
        format!(
            "batched: {} landed in a push whose tip is {short}; evaluating the tip's runs",
            sha.chars().take(8).collect::<String>()
        )
    });
    Outcome::Judged(Resolved {
        evaluation,
        runs_json,
        sha: tip,
        note,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    type P = (&'static str, &'static str, &'static str);

    // Real data, from the repository activity and compare APIs.
    const P_4090_4091: P = (
        "5813a8808b7e9944431847ccc88ed70b03c79459",
        "11e146c155ffc9f5117b11594680cb482f0b8dc2",
        "2026-10-31T08:18:18Z",
    );
    const P_NEXT: P = (
        "11e146c155ffc9f5117b11594680cb482f0b8dc2",
        "d488ac9935e16c6f8e456134d120d57c75f2f5b7",
        "2026-10-31T08:19:47Z",
    );
    const P_4092_4095: P = (
        "1a356c76bd43d1e98f3a5e7651d3061f9c853dac",
        "2a80e85babcd31063963dca008f7167e6fbc1a16",
        "2026-10-31T09:04:31Z",
    );
    const P_4098_4100: P = (
        "2a80e85babcd31063963dca008f7167e6fbc1a16",
        "276357b8ba7909de3449663e2bbf24da12bf12dc",
        "2026-10-31T09:44:59Z",
    );
    const S_4090: &str = "7f179efe6663bf84e22ec0b7379e609cfa7c944c";
    const S_4092: &str = "2ae410293665878d88dc1311257e801e30c20248";
    const S_4099: &str = "09e640a7d32b2b9f5f145af0eedc423894a6a4a6";
    const S_4098: &str = "34376c11f0aec388ff25a6d4da205e129aec2af8";

    // Newest first, as the API sends them (the real entries, trimmed).
    fn activity_json() -> String {
        let one = |p: P| {
            format!(
                r#"{{"before":"{}","after":"{}","timestamp":"{}","ref":"refs/heads/main","activity_type":"merge_queue_merge"}}"#,
                p.0, p.1, p.2
            )
        };
        format!(
            "[{}]",
            [P_4098_4100, P_4092_4095, P_NEXT, P_4090_4091]
                .map(one)
                .join(",")
        )
    }

    fn range_json(before: &str, after: &str) -> Result<String, String> {
        let shas: Vec<&str> = if (before, after) == (P_4090_4091.0, P_4090_4091.1) {
            vec![S_4090, P_4090_4091.1]
        } else if (before, after) == (P_4092_4095.0, P_4092_4095.1) {
            vec![S_4092, P_4092_4095.1]
        } else if (before, after) == (P_4098_4100.0, P_4098_4100.1) {
            vec![S_4099, S_4098, P_4098_4100.1]
        } else {
            vec![after]
        };
        let list: Vec<String> = shas.iter().map(|s| format!(r#"{{"sha":"{s}"}}"#)).collect();
        Ok(format!(
            r#"{{"total_commits":{},"commits":[{}]}}"#,
            shas.len(),
            list.join(",")
        ))
    }

    fn run(sha: &str, status: &str, concl: &str, at: &str) -> String {
        let c = if concl.is_empty() {
            "null".to_string()
        } else {
            format!("\"{concl}\"")
        };
        format!(
            r#"{{"id":1,"workflow_id":1,"name":"CI","event":"push","head_branch":"main","head_sha":"{sha}","status":"{status}","conclusion":{c},"created_at":"{at}"}}"#
        )
    }

    /// Push runs exist for the tips only; every other SHA has none.
    fn runs_for_tips(
        status: &'static str,
        concl: &'static str,
    ) -> impl Fn(&str) -> Result<String, String> {
        move |sha: &str| {
            let tips = [P_4090_4091.1, P_4092_4095.1, P_4098_4100.1, P_NEXT.1];
            let body = if tips.contains(&sha) {
                run(sha, status, concl, "2026-10-31T06:00:00Z")
            } else {
                String::new()
            };
            Ok(format!(r#"{{"workflow_runs":[{body}]}}"#))
        }
    }

    fn at(ts: &str) -> i64 {
        parse_utc(ts).unwrap()
    }

    fn act() -> Result<String, String> {
        Ok(activity_json())
    }

    fn go(sha: &str, now: i64, runs: &dyn Fn(&str) -> Result<String, String>) -> Outcome {
        resolve(sha, "main", now, 60, &act, &range_json, runs)
    }

    fn judged(o: Outcome) -> Resolved {
        match o {
            Outcome::Judged(r) => r,
            Outcome::Waiting(w) => panic!("expected a verdict, got waiting: {w}"),
        }
    }

    /// Fail-before: with no batch handling the squash SHA has no push runs, so
    /// the answer is "no runs" and watch-pr times out (exit 2).
    #[test]
    fn each_real_batch_is_judged_by_its_own_push_tip() {
        let ok = runs_for_tips("completed", "success");
        let late = at("2026-10-31T10:30:00Z");
        for (sha, tip) in [
            (S_4090, P_4090_4091.1),
            (S_4092, P_4092_4095.1),
            (S_4099, P_4098_4100.1),
            (S_4098, P_4098_4100.1),
            (P_4098_4100.1, P_4098_4100.1),
        ] {
            let r = judged(go(sha, late, &ok));
            assert_eq!((r.evaluation.status, r.sha.as_str()), (0, tip), "{sha}");
            assert_eq!(r.note.is_some(), sha != tip, "{sha}");
        }
    }

    #[test]
    fn the_tips_failure_and_in_flight_state_carry_over() {
        let late = at("2026-10-31T10:30:00Z");
        let failed = runs_for_tips("completed", "failure");
        assert_eq!(judged(go(S_4090, late, &failed)).evaluation.status, 1);
        let flight = runs_for_tips("in_progress", "");
        assert_eq!(judged(go(S_4090, late, &flight)).evaluation.status, 2);
    }

    /// 7f179efe was committed 82 minutes before its push. Settle runs from the
    /// push, so ten seconds after landing it is still settling.
    #[test]
    fn settle_runs_from_the_push_not_from_the_commit() {
        let ok = runs_for_tips("completed", "success");
        let r = judged(go(S_4090, at(P_4090_4091.2) + 10, &ok));
        assert_eq!(r.evaluation.status, 2);
        assert!(
            r.evaluation.stdout.starts_with("settling: 50s left"),
            "{}",
            r.evaluation.stdout
        );
        let r = judged(go(S_4090, at(P_4090_4091.2) + 60, &ok));
        assert_eq!(r.evaluation.status, 0);
    }

    /// The git-log walk judged the first later commit with runs. A commit that
    /// is in no recorded push must wait, not borrow an unrelated push's runs.
    #[test]
    fn a_commit_in_no_known_push_waits_and_never_borrows_a_later_push() {
        let unknown = "feedface00000000000000000000000000000000";
        let ok = runs_for_tips("completed", "success");
        match go(unknown, at("2026-10-31T10:30:00Z"), &ok) {
            Outcome::Waiting(w) => assert!(w.contains("not in the"), "{w}"),
            Outcome::Judged(_) => panic!("judged a commit that is in no push"),
        }
    }

    #[test]
    fn api_failures_wait_instead_of_reading_as_zero_runs() {
        let late = at("2026-10-31T10:30:00Z");
        let ok = runs_for_tips("completed", "success");
        let waiting = |o: Outcome| matches!(o, Outcome::Waiting(_));
        let bad_activity = || Err("HTTP 502".to_string());
        assert!(waiting(resolve(
            S_4090,
            "main",
            late,
            60,
            &bad_activity,
            &range_json,
            &ok
        )));
        let err_body = || Ok(r#"{"message":"Server Error"}"#.to_string());
        assert!(waiting(resolve(
            S_4090,
            "main",
            late,
            60,
            &err_body,
            &range_json,
            &ok
        )));
        let bad_range = |_: &str, _: &str| Err("HTTP 500".to_string());
        assert!(waiting(resolve(
            S_4090, "main", late, 60, &act, &bad_range, &ok
        )));
        let bad_runs = |_: &str| Err("HTTP 503".to_string());
        assert!(waiting(go(S_4090, late, &bad_runs)));
        let message_runs = |_: &str| Ok(r#"{"message":"API rate limit exceeded"}"#.to_string());
        assert!(waiting(go(S_4090, late, &message_runs)));
    }

    #[test]
    fn zero_runs_on_the_tip_is_still_not_green() {
        let none = |_: &str| Ok(r#"{"workflow_runs":[]}"#.to_string());
        let r = judged(go(S_4090, at("2026-10-31T10:30:00Z"), &none));
        assert_eq!(r.evaluation.status, 3);
    }

    #[test]
    fn pushes_are_searched_newest_first_and_only_as_needed() {
        let calls = RefCell::new(0);
        let counting = |b: &str, a: &str| {
            *calls.borrow_mut() += 1;
            range_json(b, a)
        };
        let ok = runs_for_tips("completed", "success");
        let late = at("2026-10-31T10:30:00Z");
        let _ = resolve(S_4099, "main", late, 60, &act, &counting, &ok);
        assert_eq!(*calls.borrow(), 1, "the newest push holds it: one compare");
    }

    #[test]
    fn parsers_reject_what_is_not_the_expected_shape() {
        assert!(parse_activity("{}").is_err());
        assert!(parse_activity("nope").is_err());
        assert_eq!(parse_activity(&activity_json()).unwrap().len(), 4);
        assert!(parse_range(r#"{"total_commits":150,"commits":[{"sha":"a"}]}"#).is_err());
        assert!(parse_range("{}").is_err());
    }
}
