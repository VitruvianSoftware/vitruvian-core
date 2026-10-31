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

//! `evaluate_runs_json` and the two run listings from pipeline-status.sh, as
//! the script's jq branch computes them (jq is the branch it takes first).

use crate::jq::{compare, interpolate, parse_stream, Input, Value};

/// What `evaluate_runs_json` leaves: what it echoes, what it returns, and
/// what jq said on stderr along the way.
#[derive(Debug, PartialEq)]
pub struct Evaluation {
    /// `echo "$msg"`, newline included.
    pub stdout: String,
    /// `return "$rc"`.
    pub status: i32,
    pub stderr: String,
}

/// bash 3.2 (macOS's /bin/bash) answers `return ""` with 255, which the
/// script's `case` sends to its "no runs" branch, as the python branch does.
/// bash 5 answers 2; the jq filter only yields nothing when every input
/// value is one it cannot index, so the difference never reaches GitHub's
/// real answers.
pub const EMPTY_RETURN_STATUS: i32 = 255;

const FAILED: [&str; 3] = ["failure", "timed_out", "startup_failure"];
const IN_FLIGHT: [&str; 4] = ["in_progress", "queued", "pending", "waiting"];
const PASSED: [&str; 3] = ["success", "skipped", "neutral"];

fn any_str(v: &Value, set: &[&str]) -> bool {
    set.iter().any(|s| v.is_str(s))
}

fn jq_error(line: usize, msg: &str) -> String {
    format!("jq: error (at <stdin>:{line}): {msg}\n")
}

/// The evaluation filter for one input value.
fn evaluate_value(v: &Value) -> Result<String, String> {
    let runs = v.index("workflow_runs")?;
    let mut named: Vec<Value> = Vec::new();
    for run in runs.iterate_quiet() {
        let keep = !run.index("name")?.is_null() || !run.index("workflow_id")?.is_null();
        if keep {
            named.push(run);
        }
    }
    // group_by(.workflow_id // .name)
    let mut keyed: Vec<(Value, Value)> = Vec::new();
    for run in named {
        let id = run.index("workflow_id")?;
        let key = if id.truthy() { id } else { run.index("name")? };
        keyed.push((key, run));
    }
    keyed.sort_by(|a, b| compare(&a.0, &b.0));
    let mut groups: Vec<Vec<Value>> = Vec::new();
    let mut last_key: Option<Value> = None;
    for (key, run) in keyed {
        let same = matches!(&last_key, Some(k) if compare(k, &key) == std::cmp::Ordering::Equal);
        if same {
            groups.last_mut().expect("group").push(run);
        } else {
            groups.push(vec![run]);
            last_key = Some(key);
        }
    }
    // map(sort_by(.id // 0) | last)
    let mut latest: Vec<Value> = Vec::new();
    for group in groups {
        let mut by_id: Vec<(Value, Value)> = Vec::new();
        for run in group {
            let id = run.index("id")?;
            let key = if id.truthy() {
                id
            } else {
                Value::Number(0.0, Some(0))
            };
            by_id.push((key, run));
        }
        by_id.sort_by(|a, b| compare(&a.0, &b.0));
        latest.push(by_id.pop().expect("non-empty group").1);
    }
    if latest.is_empty() {
        return Ok("NO_RUNS|3".to_string());
    }
    let mut failed = 0;
    let mut in_flight = 0;
    let mut passed = 0;
    for run in &latest {
        if any_str(&run.index("conclusion")?, &FAILED) {
            failed += 1;
        }
        if any_str(&run.index("status")?, &IN_FLIGHT) {
            in_flight += 1;
        }
        if any_str(&run.index("conclusion")?, &PASSED) {
            passed += 1;
        }
    }
    let total = latest.len();
    Ok(if failed > 0 {
        format!("FAILED: {failed} failed, {in_flight} in-flight, {passed} passed out of {total} total|1")
    } else if in_flight > 0 {
        format!("IN_PROGRESS: {in_flight} in-flight, {passed} passed out of {total} total|2")
    } else {
        format!("ALL_PASSED: {passed} passed out of {total} total|0")
    })
}

/// Run a per-value filter over jq's input stream (`echo "$json" | jq -r`):
/// the lines it prints and what it says on stderr.
fn run_filter<F>(json: &str, filter: F) -> (Vec<String>, String)
where
    F: Fn(&Value) -> Result<Vec<String>, String>,
{
    let input = format!("{json}\n");
    let mut lines = Vec::new();
    let mut stderr = String::new();
    for item in parse_stream(&input) {
        match item {
            Input::Value(v, line) => match filter(&v) {
                Ok(out) => lines.extend(out),
                Err(msg) => stderr.push_str(&jq_error(line, &msg)),
            },
            Input::ParseError(msg) => stderr.push_str(&format!("jq: parse error: {msg}\n")),
        }
    }
    (lines, stderr)
}

/// `evaluate_runs_json "$json"`.
pub fn evaluate_runs_json(json: &str) -> Evaluation {
    let (lines, stderr) = run_filter(json, |v| evaluate_value(v).map(|s| vec![s]));
    let data = lines.join("\n");
    let (msg, rc) = match data.rfind('|') {
        Some(at) => (&data[..at], &data[at + 1..]),
        None => (data.as_str(), data.as_str()),
    };
    let status = match rc.parse::<i32>() {
        Ok(n) => n & 0xff,
        Err(_) => EMPTY_RETURN_STATUS,
    };
    Evaluation {
        stdout: format!("{msg}\n"),
        status,
        stderr,
    }
}

/// `.workflow_runs[]? | select(<pred>) | "<line>"` over every input value.
fn list_runs<P, L>(json: &str, pred: P, line: L) -> (String, String)
where
    P: Fn(&Value) -> Result<bool, String>,
    L: Fn(&Value) -> Result<String, String>,
{
    let (lines, stderr) = run_filter(json, |v| {
        let mut out = Vec::new();
        for run in v.index("workflow_runs")?.iterate_quiet() {
            if pred(&run)? {
                out.push(line(&run)?);
            }
        }
        Ok(out)
    });
    let mut stdout = String::new();
    for l in lines {
        stdout.push_str(&l);
        stdout.push('\n');
    }
    (stdout, stderr)
}

/// The FAILED branch's listing: `  - <name>: <html_url>` per failed or timed
/// out run (every run, not only each workflow's latest), and jq's stderr.
pub fn list_failed(json: &str) -> (String, String) {
    list_runs(
        json,
        |r| {
            let c = r.index("conclusion")?;
            Ok(c.is_str("failure") || c.is_str("timed_out"))
        },
        |r| {
            Ok(format!(
                "  - {}: {}",
                interpolate(&r.index("name")?),
                interpolate(&r.index("html_url")?)
            ))
        },
    )
}

/// The IN PROGRESS branch's listing: `  - <name> (<status>): <html_url>`.
pub fn list_in_flight(json: &str) -> (String, String) {
    list_runs(
        json,
        |r| {
            let s = r.index("status")?;
            Ok(s.is_str("in_progress") || s.is_str("queued"))
        },
        |r| {
            Ok(format!(
                "  - {} ({}): {}",
                interpolate(&r.index("name")?),
                interpolate(&r.index("status")?),
                interpolate(&r.index("html_url")?)
            ))
        },
    )
}

/// Keep only the runs a push to `branch` started for exactly `sha`.
///
/// The Actions API's `head_sha` filter also returns the merge queue's
/// `merge_group` runs and any `pull_request` runs for that commit. A squash
/// landed by the queue shares its SHA with the queue's trial commit, so those
/// earlier, finished runs would otherwise be counted as the post-merge
/// pipeline (PR 4087: 11 merge_group runs read as "11 passed out of 11" while
/// the real push runs had not registered). Anything that is not an object
/// with a `workflow_runs` array is returned untouched.
pub fn restrict_to_push(json: &str, sha: &str, branch: &str) -> String {
    let Ok(mut doc) = serde_json::from_str::<serde_json::Value>(json) else {
        return json.to_string();
    };
    let Some(runs) = doc.get_mut("workflow_runs").and_then(|r| r.as_array_mut()) else {
        return json.to_string();
    };
    runs.retain(|r| {
        r.get("event").and_then(|v| v.as_str()) == Some("push")
            && r.get("head_branch").and_then(|v| v.as_str()) == Some(branch)
            && r.get("head_sha").and_then(|v| v.as_str()) == Some(sha)
    });
    let n = runs.len();
    doc["total_count"] = serde_json::Value::from(n);
    doc.to_string()
}

/// Seconds since the Unix epoch for `YYYY-MM-DDTHH:MM:SSZ`.
pub(crate) fn parse_utc(ts: &str) -> Option<i64> {
    let b = ts.as_bytes();
    if b.len() < 19 {
        return None;
    }
    let n = |a: usize, z: usize| ts.get(a..z)?.parse::<i64>().ok();
    let (y, m, d) = (n(0, 4)?, n(5, 7)?, n(8, 10)?);
    let (hh, mm, ss) = (n(11, 13)?, n(14, 16)?, n(17, 19)?);
    let y2 = if m <= 2 { y - 1 } else { y };
    let era = y2.div_euclid(400);
    let yoe = y2 - era * 400;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146097 + doe - 719468;
    Some(days * 86400 + hh * 3600 + mm * 60 + ss)
}

/// How long the earliest push run must have existed before an all-done set
/// counts as green.
pub const DEFAULT_SETTLE_SECS: i64 = 60;

/// `PIPELINE_SETTLE_SECS` as set (`None` when unset). Unset, empty or
/// unparsable all mean the default; only an explicit number overrides it, and
/// a negative one is read as 0 (no settle window).
pub fn parse_settle(raw: Option<&str>) -> i64 {
    match raw.and_then(|r| r.trim().parse::<i64>().ok()) {
        Some(n) => n.max(0),
        None => DEFAULT_SETTLE_SECS,
    }
}

/// The settle window from the environment.
pub fn settle_secs_from_env() -> i64 {
    parse_settle(std::env::var("PIPELINE_SETTLE_SECS").ok().as_deref())
}

/// The runs query: server-side narrowed to pushes on `branch`, so a tip commit
/// with many merge_group / pull_request runs cannot push the push runs off the
/// first page. The client-side filter still applies on top.
pub fn runs_query(repo: &str, sha: &str, branch: &str) -> String {
    format!("repos/{repo}/actions/runs?head_sha={sha}&event=push&branch={branch}&per_page=100")
}

/// Seconds the push runs still have to age before green may be reported: the
/// earliest run must be `settle_secs` old. GitHub creates a push's workflows
/// over a few seconds and quick ones (path-filter skips, tiny jobs) finish
/// before the slow ones appear, so "everything listed is done" is not yet
/// "everything is done". 0 means settled (or nothing to wait on).
pub fn settle_remaining(json: &str, now_epoch: i64, settle_secs: i64) -> i64 {
    if settle_secs <= 0 {
        return 0;
    }
    let Ok(doc) = serde_json::from_str::<serde_json::Value>(json) else {
        return 0;
    };
    let earliest = doc
        .get("workflow_runs")
        .and_then(|r| r.as_array())
        .into_iter()
        .flatten()
        .filter_map(|r| {
            r.get("created_at")
                .and_then(|v| v.as_str())
                .and_then(parse_utc)
        })
        .min();
    match earliest {
        Some(t) => (settle_secs - (now_epoch - t)).max(0),
        None => 0,
    }
}

/// The whole verdict for one commit's raw runs listing: keep only the push to
/// `branch` for `sha`, evaluate, and hold green back while the settle window
/// is open. Returns the verdict and the filtered listing (for the failed /
/// in-flight listings).
pub fn assess(
    raw_json: &str,
    sha: &str,
    branch: &str,
    now_epoch: i64,
    settle_secs: i64,
) -> (Evaluation, String) {
    let json = restrict_to_push(raw_json, sha, branch);
    let mut evaluation = evaluate_runs_json(&json);
    if evaluation.status == 0 {
        let left = settle_remaining(&json, now_epoch, settle_secs);
        if left > 0 {
            evaluation.stdout = format!(
                "settling: {left}s left before green; {} (more push workflows may still register)\n",
                evaluation.stdout.trim_end()
            );
            evaluation.status = 2;
        }
    }
    (evaluation, json)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(json: &str) -> (String, i32) {
        let e = evaluate_runs_json(json);
        (e.stdout, e.status)
    }

    #[test]
    fn the_shell_tests_cases() {
        assert_eq!(
            eval(r#"{"total_count":0,"workflow_runs":[]}"#),
            ("NO_RUNS\n".into(), 3)
        );
        let green = r#"{"workflow_runs":[{"name":"CI","status":"completed","conclusion":"success"},{"name":"delivery","status":"completed","conclusion":"skipped"}]}"#;
        assert_eq!(
            eval(green),
            ("ALL_PASSED: 2 passed out of 2 total\n".into(), 0)
        );
        let flight = r#"{"workflow_runs":[{"name":"CI","status":"completed","conclusion":"success"},{"name":"delivery","status":"in_progress","conclusion":null}]}"#;
        assert_eq!(
            eval(flight),
            (
                "IN_PROGRESS: 1 in-flight, 1 passed out of 2 total\n".into(),
                2
            )
        );
        let failed = r#"{"workflow_runs":[{"name":"CI","status":"completed","conclusion":"failure"},{"name":"delivery","status":"in_progress","conclusion":null}]}"#;
        assert_eq!(
            eval(failed),
            (
                "FAILED: 1 failed, 1 in-flight, 0 passed out of 2 total\n".into(),
                1
            )
        );
    }

    #[test]
    fn latest_run_per_workflow_wins() {
        let rerun = r#"{"workflow_runs":[
            {"id":2,"workflow_id":7,"name":"CI","status":"completed","conclusion":"success"},
            {"id":1,"workflow_id":7,"name":"CI","status":"completed","conclusion":"failure"}]}"#;
        assert_eq!(
            eval(rerun),
            ("ALL_PASSED: 1 passed out of 1 total\n".into(), 0)
        );
        let ties = r#"{"workflow_runs":[
            {"workflow_id":7,"conclusion":"failure"},
            {"workflow_id":7,"conclusion":"success"}]}"#;
        assert_eq!(
            eval(ties),
            ("ALL_PASSED: 1 passed out of 1 total\n".into(), 0)
        );
    }

    #[test]
    fn workflow_id_zero_is_a_key_and_false_falls_back_to_name() {
        let runs = r#"{"workflow_runs":[
            {"workflow_id":0,"name":"a","conclusion":"success"},
            {"workflow_id":false,"name":"b","conclusion":"success"},
            {"workflow_id":false,"name":"b","conclusion":"success"}]}"#;
        assert_eq!(
            eval(runs),
            ("ALL_PASSED: 2 passed out of 2 total\n".into(), 0)
        );
    }

    #[test]
    fn unnamed_runs_are_ignored() {
        assert_eq!(
            eval(r#"{"workflow_runs":[{"conclusion":"failure"},null]}"#),
            ("NO_RUNS\n".into(), 3)
        );
    }

    #[test]
    fn a_stream_of_values_returns_the_last_status() {
        let both = "{\"message\":\"Not Found\"}\n{\"total_count\":0,\"workflow_runs\":[]}";
        assert_eq!(eval(both), ("NO_RUNS|3\nNO_RUNS\n".into(), 3));
    }

    #[test]
    fn values_jq_cannot_index_print_errors_and_nothing_else() {
        let e = evaluate_runs_json("5");
        assert_eq!((e.stdout.as_str(), e.status), ("\n", EMPTY_RETURN_STATUS));
        assert_eq!(
            e.stderr,
            "jq: error (at <stdin>:1): Cannot index number with string \"workflow_runs\"\n"
        );
        let e = evaluate_runs_json(r#"{"workflow_runs":[1]}"#);
        assert_eq!(
            e.stderr,
            "jq: error (at <stdin>:1): Cannot index number with string \"name\"\n"
        );
        assert_eq!(evaluate_runs_json("").status, EMPTY_RETURN_STATUS);
    }

    #[test]
    fn listings() {
        let runs = r#"{"workflow_runs":[
            {"name":"CI","status":"completed","conclusion":"failure","html_url":"u1"},
            {"name":"D","status":"queued","conclusion":null},
            {"name":"E","status":"completed","conclusion":"timed_out","html_url":"u3"}]}"#;
        assert_eq!(list_failed(runs).0, "  - CI: u1\n  - E: u3\n");
        assert_eq!(list_in_flight(runs).0, "  - D (queued): null\n");
    }

    fn run(
        id: u64,
        name: &str,
        event: &str,
        branch: &str,
        status: &str,
        concl: &str,
        at: &str,
    ) -> String {
        let c = if concl.is_empty() {
            "null".to_string()
        } else {
            format!("\"{concl}\"")
        };
        format!(
            r#"{{"id":{id},"workflow_id":{id},"name":"{name}","event":"{event}","head_branch":"{branch}","head_sha":"abc","status":"{status}","conclusion":{c},"created_at":"{at}"}}"#
        )
    }

    /// PR 4087: eleven finished merge_group runs share the squash SHA; the
    /// push runs are not there yet (or only some are, still running).
    #[test]
    fn merge_group_runs_are_not_the_post_merge_pipeline() {
        let mq: Vec<String> = (1..=11)
            .map(|i| {
                run(
                    i,
                    &format!("w{i}"),
                    "merge_group",
                    "gh-readonly-queue/main/pr-1-x",
                    "completed",
                    "success",
                    "2026-10-31T06:26:44Z",
                )
            })
            .collect();
        let json = format!(r#"{{"workflow_runs":[{}]}}"#, mq.join(","));
        // Unfiltered (the old behaviour): a false green.
        assert_eq!(eval(&json).1, 0);
        // Filtered: nothing has run for the push yet.
        assert_eq!(
            eval(&restrict_to_push(&json, "abc", "main")),
            ("NO_RUNS\n".into(), 3)
        );
        // Push runs registered and in flight alongside: not green.
        let push = run(
            50,
            "Presubmit",
            "push",
            "main",
            "in_progress",
            "",
            "2026-10-31T06:54:06Z",
        );
        let json = format!(r#"{{"workflow_runs":[{},{}]}}"#, mq.join(","), push);
        assert_eq!(eval(&restrict_to_push(&json, "abc", "main")).1, 2);
    }

    #[test]
    fn restrict_is_strict_on_sha_branch_and_event() {
        let rs = [
            run(
                1,
                "a",
                "push",
                "main",
                "completed",
                "success",
                "2026-10-31T06:54:06Z",
            ),
            run(
                2,
                "b",
                "push",
                "feature",
                "completed",
                "failure",
                "2026-10-31T06:54:06Z",
            ),
            run(
                3,
                "c",
                "pull_request",
                "main",
                "completed",
                "failure",
                "2026-10-31T06:54:06Z",
            ),
            run(
                4,
                "d",
                "push",
                "main",
                "completed",
                "failure",
                "2026-10-31T06:54:06Z",
            )
            .replace("\"abc\"", "\"other\""),
        ];
        let json = format!(r#"{{"workflow_runs":[{}]}}"#, rs.join(","));
        assert_eq!(
            eval(&restrict_to_push(&json, "abc", "main")),
            ("ALL_PASSED: 1 passed out of 1 total\n".into(), 0)
        );
    }

    #[test]
    fn utc_parsing_and_settle_window() {
        assert_eq!(parse_utc("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(parse_utc("2026-10-31T06:54:06Z"), Some(1793429646));
        let json = format!(
            r#"{{"workflow_runs":[{}]}}"#,
            run(
                1,
                "a",
                "push",
                "main",
                "completed",
                "success",
                "2026-10-31T06:54:06Z"
            )
        );
        let t = 1793429646;
        assert_eq!(settle_remaining(&json, t + 3, 60), 57);
        assert_eq!(settle_remaining(&json, t + 60, 60), 0);
        assert_eq!(settle_remaining(&json, t + 3, 0), 0);
        assert_eq!(settle_remaining(r#"{"workflow_runs":[]}"#, t, 60), 0);
    }

    const T: i64 = 1793429646; // 2026-10-31T06:54:06Z

    fn done_push_json() -> String {
        format!(
            r#"{{"workflow_runs":[{}]}}"#,
            run(
                1,
                "a",
                "push",
                "main",
                "completed",
                "success",
                "2026-10-31T06:54:06Z"
            )
        )
    }

    #[test]
    fn unset_or_garbage_settle_means_the_default_not_zero() {
        assert_eq!(DEFAULT_SETTLE_SECS, 60);
        assert_eq!(parse_settle(None), 60);
        assert_eq!(parse_settle(Some("")), 60);
        assert_eq!(parse_settle(Some("soon")), 60);
        assert_eq!(parse_settle(Some("15")), 15);
        assert_eq!(parse_settle(Some("0")), 0);
        assert_eq!(parse_settle(Some("-5")), 0);
    }

    #[test]
    fn green_is_held_back_by_the_default_settle_window() {
        let default = parse_settle(None);
        let (e, _) = assess(&done_push_json(), "abc", "main", T + 3, default);
        assert_eq!(e.status, 2, "all-done set 3s old must not be green");
        assert!(e.stdout.starts_with("settling: 57s left"), "{}", e.stdout);
        let (e, _) = assess(&done_push_json(), "abc", "main", T + 60, default);
        assert_eq!(
            (e.status, e.stdout.as_str()),
            (0, "ALL_PASSED: 1 passed out of 1 total\n")
        );
    }

    #[test]
    fn settle_never_masks_a_failure() {
        let json = format!(
            r#"{{"workflow_runs":[{}]}}"#,
            run(
                1,
                "a",
                "push",
                "main",
                "completed",
                "failure",
                "2026-10-31T06:54:06Z"
            )
        );
        assert_eq!(assess(&json, "abc", "main", T + 1, 60).0.status, 1);
    }

    #[test]
    fn the_runs_query_asks_github_for_pushes_on_the_branch() {
        let q = runs_query("o/r", "abc", "main");
        assert!(
            q.contains("head_sha=abc&event=push&branch=main&per_page=100"),
            "{q}"
        );
    }
}
