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

//! GitHub pull request parsers (`gh search prs`, `gh pr view`).

use crate::json::{JsonMap, JsonValue};
use crate::time_util::Timestamp;

/// The check rollup of one PR, counted rather than listed.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Checks {
    pub success: i32,
    pub failure: i32,
    pub pending: i32,
    pub skipped: i32,
}

impl Checks {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("success", JsonValue::from_i32(self.success));
        m.insert("failure", JsonValue::from_i32(self.failure));
        m.insert("pending", JsonValue::from_i32(self.pending));
        m.insert("skipped", JsonValue::from_i32(self.skipped));
        JsonValue::Object(m)
    }
}

/// One row of `GET /v1/prs`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct PR {
    pub repo: String,
    pub number: i32,
    pub title: String,
    pub url: String,
    pub author: String,
    pub is_draft: bool,
    pub head_ref: String,
    pub base_ref: String,
    pub merge_state: String,
    pub review_decision: String,
    pub checks: Checks,
    pub auto_merge: bool,
    pub updated_at: Timestamp,
}

impl PR {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("repo", JsonValue::from_str_val(&self.repo));
        m.insert("number", JsonValue::from_i32(self.number));
        m.insert("title", JsonValue::from_str_val(&self.title));
        m.insert("url", JsonValue::from_str_val(&self.url));
        m.insert("author", JsonValue::from_str_val(&self.author));
        m.insert("is_draft", JsonValue::from_bool(self.is_draft));
        m.insert("head_ref", JsonValue::from_str_val(&self.head_ref));
        m.insert("base_ref", JsonValue::from_str_val(&self.base_ref));
        m.insert("merge_state", JsonValue::from_str_val(&self.merge_state));
        m.insert(
            "review_decision",
            JsonValue::from_str_val(&self.review_decision),
        );
        m.insert("checks", self.checks.to_json_value());
        m.insert("auto_merge", JsonValue::from_bool(self.auto_merge));
        m.insert(
            "updated_at",
            JsonValue::from_str_val(self.updated_at.to_rfc3339()),
        );
        JsonValue::Object(m)
    }
}

/// Body of `GET /v1/prs`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct PRs {
    pub available: bool,
    pub reason: String,
    pub sampled_at: Timestamp,
    pub prs: Vec<PR>,
}

impl PRs {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("available", JsonValue::from_bool(self.available));
        m.insert("reason", JsonValue::from_str_val(&self.reason));
        m.insert(
            "sampled_at",
            JsonValue::from_str_val(self.sampled_at.to_rfc3339()),
        );
        m.insert(
            "prs",
            JsonValue::Array(self.prs.iter().map(|p| p.to_json_value()).collect()),
        );
        JsonValue::Object(m)
    }

    pub fn to_json_string(&self) -> String {
        self.to_json_value().to_json_string()
    }
}

/// One row of `gh search prs`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct PRRef {
    pub repo: String,
    pub number: i32,
    pub title: String,
    pub url: String,
    pub updated_at: Timestamp,
}

/// Reads `gh search prs --json number,repository,title,url,updatedAt`.
pub fn parse_gh_search_prs(out: &str) -> Result<Vec<PRRef>, String> {
    let val = JsonValue::parse(out).map_err(|e| format!("gh search prs: {}", e))?;
    let rows = val
        .as_array()
        .ok_or_else(|| "gh search prs: expected JSON array".to_string())?;
    let mut refs = Vec::with_capacity(rows.len());
    for r in rows {
        let repo = r
            .get("repository")
            .map(|rep| rep.get_str("nameWithOwner"))
            .unwrap_or("")
            .to_string();
        let number = r.get_i32("number");
        let title = r.get_str("title").to_string();
        let url = r.get_str("url").to_string();
        let updated_at =
            Timestamp::parse_rfc3339(r.get_str("updatedAt")).unwrap_or(Timestamp::ZERO);
        refs.push(PRRef {
            repo,
            number,
            title,
            url,
            updated_at,
        });
    }
    Ok(refs)
}

/// Reads `gh pr view <n> --json isDraft,headRefName,baseRefName,mergeStateStatus,reviewDecision,statusCheckRollup,autoMergeRequest,author`.
pub fn parse_gh_pr_view(out: &str) -> Result<PR, String> {
    let raw = JsonValue::parse(out).map_err(|e| format!("gh pr view: {}", e))?;
    let v = raw
        .as_object()
        .ok_or_else(|| "gh pr view: expected JSON object".to_string())?;

    let mut pr = PR {
        is_draft: v.get_bool("isDraft"),
        head_ref: v.get_str("headRefName").to_string(),
        base_ref: v.get_str("baseRefName").to_string(),
        merge_state: v.get_str("mergeStateStatus").to_string(),
        review_decision: v.get_str("reviewDecision").to_string(),
        author: v
            .get("author")
            .map(|a| a.get_str("login"))
            .unwrap_or("")
            .to_string(),
        auto_merge: v
            .get("autoMergeRequest")
            .map(|amr| !amr.is_null())
            .unwrap_or(false),
        ..Default::default()
    };

    if let Some(rollup) = v.get("statusCheckRollup").and_then(|r| r.as_array()) {
        for c in rollup {
            let mut signal = c.get_str("conclusion");
            if signal.is_empty() {
                signal = c.get_str("state");
            }
            if signal.is_empty() {
                signal = c.get_str("status");
            }
            match signal {
                "SUCCESS" => pr.checks.success += 1,
                "SKIPPED" | "NEUTRAL" => pr.checks.skipped += 1,
                "PENDING" | "IN_PROGRESS" | "QUEUED" | "WAITING" | "REQUESTED" | "EXPECTED" => {
                    pr.checks.pending += 1
                }
                _ => pr.checks.failure += 1,
            }
        }
    }

    Ok(pr)
}

/// Collapses a rollup into `"red"`, `"green"`, or `""`.
pub fn pr_checks_verdict(c: &Checks) -> &'static str {
    if c.pending > 0 {
        ""
    } else if c.failure > 0 {
        "red"
    } else if c.success > 0 {
        "green"
    } else {
        ""
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn read_fixture(name: &str) -> String {
        for candidate in [
            format!("testdata/{}", name),
            format!(
                "apps/mobile/android-remote/macagent/metrics/testdata/{}",
                name
            ),
        ] {
            if let Ok(s) = std::fs::read_to_string(&candidate) {
                return s;
            }
        }
        if let Ok(srcdir) = std::env::var("TEST_SRCDIR") {
            let p = format!(
                "{}/_main/apps/mobile/android-remote/macagent/metrics/testdata/{}",
                srcdir, name
            );
            if let Ok(s) = std::fs::read_to_string(&p) {
                return s;
            }
        }
        panic!("fixture {} not found", name);
    }

    #[test]
    fn test_parse_gh_pr_view_on_a_real_pr() {
        let data = read_fixture("gh-pr-view.json");
        let pr = parse_gh_pr_view(&data).expect("parse_gh_pr_view");
        assert_eq!(pr.head_ref, "claude/remote-polish");
        assert_eq!(pr.base_ref, "main");
        assert_eq!(pr.author, "ipv1337");
        assert_eq!(pr.merge_state, "CLEAN");
        assert!(!pr.is_draft);
        assert!(
            !pr.auto_merge,
            "auto_merge must be false when autoMergeRequest is null"
        );
        let want = Checks {
            success: 26,
            skipped: 19,
            ..Default::default()
        };
        assert_eq!(pr.checks, want);
    }

    #[test]
    fn test_parse_gh_pr_view_buckets_every_conclusion() {
        let raw = r#"{"isDraft":true,"headRefName":"wip","baseRefName":"main","mergeStateStatus":"BLOCKED",
          "reviewDecision":"CHANGES_REQUESTED","author":{"login":"someone"},"autoMergeRequest":{"enabledAt":"x"},
          "statusCheckRollup":[
            {"__typename":"CheckRun","conclusion":"SUCCESS","status":"COMPLETED"},
            {"__typename":"CheckRun","conclusion":"FAILURE","status":"COMPLETED"},
            {"__typename":"CheckRun","conclusion":"TIMED_OUT","status":"COMPLETED"},
            {"__typename":"CheckRun","conclusion":"","status":"IN_PROGRESS"},
            {"__typename":"CheckRun","conclusion":"","status":"QUEUED"},
            {"__typename":"CheckRun","conclusion":"SKIPPED","status":"COMPLETED"},
            {"__typename":"StatusContext","state":"PENDING"},
            {"__typename":"StatusContext","state":"SUCCESS"},
            {"__typename":"CheckRun","conclusion":"WHAT_IS_THIS","status":"COMPLETED"}
          ]}"#;
        let pr = parse_gh_pr_view(raw).expect("parse synthetic rollup");
        let want = Checks {
            success: 2,
            failure: 3,
            pending: 3,
            skipped: 1,
        };
        assert_eq!(pr.checks, want);
        assert!(pr.auto_merge);
        assert!(pr.is_draft);
        assert_eq!(pr.review_decision, "CHANGES_REQUESTED");
    }

    #[test]
    fn test_parse_gh_search_prs() {
        let data = read_fixture("gh-search-prs.json");
        let refs = parse_gh_search_prs(&data).expect("parse_gh_search_prs");
        assert!(!refs.is_empty(), "no PRs parsed from the fixture");
        assert_eq!(refs[0].repo, "VitruvianSoftware/vitruvian-core");
        assert_eq!(refs[0].number, 2226);
        assert!(!refs[0].updated_at.is_zero(), "updatedAt did not parse");

        let empty = parse_gh_search_prs("[]").expect("empty search");
        assert_eq!(empty.len(), 0);

        assert!(
            parse_gh_search_prs("").is_err(),
            "empty stdout must be an error, not zero PRs"
        );
    }

    #[test]
    fn test_pr_checks_verdict_waits_for_pending() {
        assert_eq!(
            pr_checks_verdict(&Checks {
                success: 20,
                pending: 1,
                ..Default::default()
            }),
            ""
        );
        assert_eq!(
            pr_checks_verdict(&Checks {
                success: 20,
                failure: 1,
                ..Default::default()
            }),
            "red"
        );
        assert_eq!(
            pr_checks_verdict(&Checks {
                success: 20,
                skipped: 4,
                ..Default::default()
            }),
            "green"
        );
        assert_eq!(pr_checks_verdict(&Checks::default()), "");
    }
}
