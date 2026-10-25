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

//! `parse_checks_json` from watch-pr.sh, as its python3 branch computes it
//! (python3 is the branch it takes first): one `passed:skipped:pending:failed`
//! line, then a `FAILED_ITEM:name|workflow|link` line per failing check.

use crate::pyjson::{loads, Value};

/// What the function prints, the status it exits with, and its stderr.
#[derive(Debug, PartialEq)]
pub struct Parsed {
    pub stdout: String,
    pub status: i32,
    pub stderr: String,
}

const FAILED_STATES: [&str; 6] = [
    "FAILURE",
    "FAILED",
    "ERROR",
    "TIMED_OUT",
    "STARTUP_FAILURE",
    "CANCELLED",
];
const PENDING_STATES: [&str; 5] = ["IN_PROGRESS", "QUEUED", "PENDING", "WAITING", ""];
const PASSED_STATES: [&str; 2] = ["SUCCESS", "NEUTRAL"];

fn traceback(line: u32, error: &str) -> Parsed {
    Parsed {
        stdout: String::new(),
        status: 1,
        stderr: format!(
            "Traceback (most recent call last):\n  File \"<string>\", line {line}, in <module>\n{error}\n"
        ),
    }
}

/// `parse_checks_json "$json"`.
pub fn parse_checks_json(json: &str) -> Parsed {
    let checks = match loads(json) {
        Ok(v) => v,
        Err(e) => {
            return Parsed {
                stdout: format!("PARSE_ERROR: {e}\n"),
                status: 3,
                stderr: String::new(),
            }
        }
    };
    // `for c in checks:` — a dict yields its keys and a str its characters,
    // neither of which has `.get`.
    let items: Vec<Value> = match checks {
        Value::List(items) => items,
        Value::Dict(entries) => entries.into_iter().map(|(k, _)| Value::Str(k)).collect(),
        Value::Str(s) => s.chars().map(|c| Value::Str(c.to_string())).collect(),
        other => {
            return traceback(
                16,
                &format!("TypeError: '{}' object is not iterable", other.type_name()),
            )
        }
    };

    let (mut passed, mut skipped, mut pending, mut failed) = (0, 0, 0, 0);
    let mut details = Vec::new();
    let empty = Value::Str(String::new());
    for c in &items {
        if !matches!(c, Value::Dict(_)) {
            return traceback(
                17,
                &format!(
                    "AttributeError: '{}' object has no attribute 'get'",
                    c.type_name()
                ),
            );
        }
        let bucket = c.get("bucket").unwrap_or(&empty);
        // str(state).upper(): only a string can come out as one of the states.
        let state = match c.get("state") {
            None => String::new(),
            Some(Value::Str(s)) => s.to_uppercase(),
            Some(other) => other.py_str().to_uppercase(),
        };
        let unknown = Value::Str("unknown".into());
        let name = c.get("name").unwrap_or(&unknown);
        let workflow = c.get("workflow").unwrap_or(&empty);
        let link = match c.get("link") {
            Some(v) if v.truthy() => v.clone(),
            _ => c.get("url").cloned().unwrap_or_else(|| empty.clone()),
        };
        let is = |want: &str| matches!(bucket, Value::Str(b) if b == want);
        let state_in = |set: &[&str]| set.iter().any(|s| *s == state);

        if is("fail") || state_in(&FAILED_STATES) {
            failed += 1;
            details.push(format!(
                "{}|{}|{}",
                name.py_str(),
                workflow.py_str(),
                link.py_str()
            ));
        } else if is("pending") || state_in(&PENDING_STATES) {
            pending += 1;
        } else if is("pass") || state_in(&PASSED_STATES) {
            passed += 1;
        } else if is("skipping") || state == "SKIPPED" {
            skipped += 1;
        } else {
            pending += 1;
        }
    }

    let mut stdout = format!("{passed}:{skipped}:{pending}:{failed}\n");
    for d in details {
        stdout.push_str("FAILED_ITEM:");
        stdout.push_str(&d);
        stdout.push('\n');
    }
    Parsed {
        stdout,
        status: 0,
        stderr: String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn out(json: &str) -> String {
        parse_checks_json(json).stdout
    }

    #[test]
    fn the_shell_tests_cases() {
        let green = r#"[{"name":"CI","state":"SUCCESS","bucket":"pass","workflow":"ci","link":"https://ci.run/1"},
                        {"name":"lint","state":"SUCCESS","bucket":"pass","workflow":"lint","link":"https://ci.run/2"}]"#;
        assert_eq!(out(green), "2:0:0:0\n");
        let failed = r#"[{"name":"unit-test","state":"FAILURE","bucket":"fail","workflow":"ci","link":"https://ci.run/99"}]"#;
        assert_eq!(
            out(failed),
            "0:0:0:1\nFAILED_ITEM:unit-test|ci|https://ci.run/99\n"
        );
        let mixed = r#"[{"name":"delivery","state":"SKIPPED","bucket":"skipping","workflow":"delivery","link":""},
                        {"name":"integration","state":"IN_PROGRESS","bucket":"pending","workflow":"ci","link":""}]"#;
        assert_eq!(out(mixed), "0:1:1:0\n");
    }

    #[test]
    fn python_edges() {
        // No state at all counts as pending; an unknown state too.
        assert_eq!(out(r#"[{"name":"a"},{"state":"stale"}]"#), "0:0:2:0\n");
        // Lower-case states are upper-cased first.
        assert_eq!(
            out(r#"[{"state":"success"},{"state":"cancelled"}]"#),
            "1:0:0:1\nFAILED_ITEM:unknown||\n"
        );
        // An empty link falls back to url; values print with str().
        assert_eq!(
            out(r#"[{"bucket":"fail","name":null,"workflow":1.0,"link":"","url":["u"]}]"#),
            "0:0:0:1\nFAILED_ITEM:None|1.0|['u']\n"
        );
        assert_eq!(out("{}"), "0:0:0:0\n");
        assert_eq!(out("\"\""), "0:0:0:0\n");
    }

    #[test]
    fn python_errors() {
        assert_eq!(parse_checks_json("5").status, 1);
        assert_eq!(parse_checks_json("[1]").status, 1);
        assert_eq!(parse_checks_json(r#"{"a":1}"#).status, 1);
        let bad = parse_checks_json("nope");
        assert_eq!(bad.status, 3);
        assert!(bad.stdout.starts_with("PARSE_ERROR: "));
    }
}
