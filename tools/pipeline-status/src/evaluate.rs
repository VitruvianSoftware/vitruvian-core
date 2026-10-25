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
}
