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

//! Is the PR still in the merge queue? One GraphQL read answers it from what
//! GitHub records, not from `mergeStateStatus`, which says whether the PR
//! *could* merge and has no "queued" value at all:
//!
//! - `mergeQueueEntry` is set while the PR is in the queue, null otherwise;
//! - the latest Added/RemovedFromMergeQueueEvent says why it left (GitHub
//!   records a merge from the queue as a removal with reason `merged`);
//! - `autoMergeRequest` is set when auto-merge is armed but the PR is not
//!   queued yet, so GitHub will add it once its checks pass.

use serde_json::Value;

pub const QUERY: &str = "query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){state mergeStateStatus mergeCommit{oid} autoMergeRequest{enabledAt} mergeQueueEntry{state position} timelineItems(last:1,itemTypes:[ADDED_TO_MERGE_QUEUE_EVENT,REMOVED_FROM_MERGE_QUEUE_EVENT]){nodes{__typename ... on AddedToMergeQueueEvent{createdAt} ... on RemovedFromMergeQueueEvent{createdAt reason}}}}}}";

/// What the watcher does next.
#[derive(Debug, PartialEq)]
pub enum Verdict {
    Merged,
    Closed,
    /// In the queue: the entry's state (QUEUED, AWAITING_CHECKS, MERGEABLE,
    /// ...) and position.
    Queued {
        state: String,
        position: i64,
    },
    /// Not queued, but auto-merge is armed, so GitHub will queue it.
    AutoMergeArmed,
    /// Left the queue by merging; GitHub has not marked the PR merged yet.
    Merging,
    /// Taken out of the queue and nothing will put it back.
    Removed {
        reason: String,
        at: String,
    },
    /// Never queued (or the last event was an add GitHub has not reflected
    /// yet): waiting for someone to enqueue it.
    NotQueued,
}

/// The parts of the answer the watcher shows, plus the verdict.
#[derive(Debug, PartialEq)]
pub struct Status {
    pub verdict: Verdict,
    pub merge_state: String,
}

fn str_at<'a>(v: &'a Value, path: &[&str]) -> Option<&'a str> {
    path.iter().try_fold(v, |v, k| v.get(k))?.as_str()
}

/// Read `gh api graphql -f query=QUERY` output. Anything that is not a
/// pull request is an error, never a guess at its state.
pub fn parse(json: &str) -> Result<Status, String> {
    let root: Value = serde_json::from_str(json).map_err(|e| format!("not JSON: {e}"))?;
    if let Some(errors) = root.get("errors").filter(|e| !e.is_null()) {
        return Err(format!("GraphQL errors: {errors}"));
    }
    let pr = root
        .pointer("/data/repository/pullRequest")
        .filter(|v| v.is_object())
        .ok_or("no pullRequest in the response")?;
    let state = str_at(pr, &["state"]).ok_or("pullRequest has no state")?;
    let merge_state = str_at(pr, &["mergeStateStatus"]).unwrap_or("").to_string();

    let verdict = match state {
        "MERGED" => Verdict::Merged,
        "CLOSED" => Verdict::Closed,
        "OPEN" => open_verdict(pr),
        other => return Err(format!("unknown pullRequest state {other:?}")),
    };
    Ok(Status {
        verdict,
        merge_state,
    })
}

fn open_verdict(pr: &Value) -> Verdict {
    if let Some(entry) = pr.get("mergeQueueEntry").filter(|e| e.is_object()) {
        return Verdict::Queued {
            state: str_at(entry, &["state"]).unwrap_or("QUEUED").to_string(),
            position: entry.get("position").and_then(Value::as_i64).unwrap_or(0),
        };
    }
    if pr.get("autoMergeRequest").is_some_and(|a| a.is_object()) {
        return Verdict::AutoMergeArmed;
    }
    let last = pr
        .pointer("/timelineItems/nodes")
        .and_then(Value::as_array)
        .and_then(|nodes| nodes.last());
    match last {
        Some(event) if str_at(event, &["__typename"]) == Some("RemovedFromMergeQueueEvent") => {
            if str_at(event, &["reason"]) == Some("merged") {
                return Verdict::Merging;
            }
            Verdict::Removed {
                reason: str_at(event, &["reason"])
                    .filter(|r| !r.is_empty())
                    .unwrap_or("unknown")
                    .to_string(),
                at: str_at(event, &["createdAt"]).unwrap_or("").to_string(),
            }
        }
        _ => Verdict::NotQueued,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pr(state: &str, extra: &str, events: &str) -> String {
        format!(
            r#"{{"data":{{"repository":{{"pullRequest":{{"state":"{state}","mergeStateStatus":"CLEAN","mergeCommit":null,{extra}"timelineItems":{{"nodes":[{events}]}}}}}}}}}}"#
        )
    }

    const REMOVED: &str = r#"{"__typename":"RemovedFromMergeQueueEvent","createdAt":"2026-11-14T01:24:44Z","reason":"checks_timed_out"}"#;
    const ADDED: &str =
        r#"{"__typename":"AddedToMergeQueueEvent","createdAt":"2026-11-14T02:20:49Z"}"#;

    fn verdict(json: &str) -> Verdict {
        parse(json).unwrap().verdict
    }

    #[test]
    fn removed_with_no_entry_is_removed() {
        let json = pr(
            "OPEN",
            r#""mergeQueueEntry":null,"autoMergeRequest":null,"#,
            REMOVED,
        );
        assert_eq!(
            verdict(&json),
            Verdict::Removed {
                reason: "checks_timed_out".into(),
                at: "2026-11-14T01:24:44Z".into()
            }
        );
        assert_eq!(parse(&json).unwrap().merge_state, "CLEAN");
    }

    #[test]
    fn an_entry_wins_over_an_old_removal() {
        let json = pr(
            "OPEN",
            r#""mergeQueueEntry":{"state":"AWAITING_CHECKS","position":2},"#,
            REMOVED,
        );
        assert_eq!(
            verdict(&json),
            Verdict::Queued {
                state: "AWAITING_CHECKS".into(),
                position: 2
            }
        );
    }

    #[test]
    fn rearmed_auto_merge_is_waiting() {
        let json = pr(
            "OPEN",
            r#""mergeQueueEntry":null,"autoMergeRequest":{"enabledAt":"x"},"#,
            REMOVED,
        );
        assert_eq!(verdict(&json), Verdict::AutoMergeArmed);
    }

    #[test]
    fn never_queued_or_just_added_is_not_queued() {
        let none = pr("OPEN", r#""mergeQueueEntry":null,"#, "");
        assert_eq!(verdict(&none), Verdict::NotQueued);
        let added = pr("OPEN", r#""mergeQueueEntry":null,"#, ADDED);
        assert_eq!(verdict(&added), Verdict::NotQueued);
    }

    #[test]
    fn merged_and_closed_come_from_state() {
        let merged_event =
            r#"{"__typename":"RemovedFromMergeQueueEvent","createdAt":"t","reason":"merged"}"#;
        assert_eq!(verdict(&pr("MERGED", "", merged_event)), Verdict::Merged);
        assert_eq!(verdict(&pr("CLOSED", "", REMOVED)), Verdict::Closed);
        let open = pr("OPEN", r#""mergeQueueEntry":null,"#, merged_event);
        assert_eq!(verdict(&open), Verdict::Merging);
    }

    #[test]
    fn anything_else_is_an_error_not_a_state() {
        assert!(parse("").is_err());
        assert!(parse("HTTP 401: Bad credentials").is_err());
        assert!(parse(r#"{"data":{"repository":{"pullRequest":null}}}"#).is_err());
        assert!(parse(r#"{"data":null,"errors":[{"message":"x"}]}"#).is_err());
    }
}
