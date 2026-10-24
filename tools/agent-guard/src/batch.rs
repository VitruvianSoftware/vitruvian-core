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

//! `agent_guard_rs --batch`: the parity test's way in. One JSON request per
//! line on stdin, one JSON answer per line on stdout. It reaches the same
//! functions agent_guard_test.py calls on the Python guard (evaluate with a
//! fixed git state, the parser, redaction, the policy loader, the git probe,
//! the installer check), so the same tests can run against this binary.
//!
//! It decides nothing for a real hook and writes nothing; the hook is the
//! binary run without arguments.

use std::io::{BufRead, Write};
use std::panic::{catch_unwind, AssertUnwindSafe};

use serde_json::{json, Value};

use crate::classify::{installer_problem, GitProbe, INSTALLER_PROBLEM_OVERRIDE};
use crate::gitstate::{probe_git_state, GitState};
use crate::guard::{evaluate, load_policy, Modes};
use crate::redact::{redact, redact_for_log};
use crate::scope::clear_caches;
use crate::shell::{
    body_substitutions, fallback_split, parse_script, strip_heredoc_bodies, PErr, SimpleCommand,
    MAX_COMMANDS,
};

fn text(req: &Value, key: &str) -> String {
    req.get(key)
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string()
}

fn commands_json(cmds: &[SimpleCommand]) -> Value {
    Value::Array(
        cmds.iter()
            .map(|c| {
                json!({
                    "words": c.words,
                    "redirects": c.redirects.iter().map(|(a, b)| json!([a, b])).collect::<Vec<_>>(),
                    "heredocs": c.heredocs,
                    "herestrings": c.herestrings,
                })
            })
            .collect(),
    )
}

fn git_state_json(s: &GitState) -> Value {
    json!({
        "merge": s.merge,
        "rebase": s.rebase,
        "cherry_pick": s.cherry_pick,
        "unmerged": s.unmerged,
        "primary": s.primary,
    })
}

fn git_state_from(v: &Value) -> GitState {
    let b = |k: &str, d: bool| v.get(k).and_then(|x| x.as_bool()).unwrap_or(d);
    GitState {
        merge: b("merge", false),
        rebase: b("rebase", false),
        cherry_pick: b("cherry_pick", false),
        unmerged: v
            .get("unmerged")
            .and_then(|u| u.as_array())
            .map(|a| {
                a.iter()
                    .filter_map(|x| x.as_str().map(|s| s.to_string()))
                    .collect()
            })
            .unwrap_or_default(),
        primary: b("primary", true),
    }
}

fn handle(req: &Value) -> Value {
    let kind = text(req, "kind");
    match kind.as_str() {
        "evaluate" => {
            let modes: Option<Modes> = req.get("modes").and_then(|m| m.as_object()).map(|m| {
                m.iter()
                    .map(|(k, v)| (k.clone(), v.as_str().unwrap_or("").to_string()))
                    .collect()
            });
            let git: Option<GitProbe> = match req.get("git_state") {
                Some(v) if v.is_object() => {
                    let st = git_state_from(v);
                    Some(Box::new(move |_d: &str| st.clone()))
                }
                _ => None,
            };
            let home = req
                .get("home")
                .and_then(|h| h.as_str())
                .map(|s| s.to_string());
            let known = req
                .get("cwd_known")
                .and_then(|k| k.as_bool())
                .unwrap_or(true);
            let d = evaluate(
                &text(req, "command"),
                &text(req, "cwd"),
                modes.as_ref(),
                home.as_deref(),
                git,
                known,
            );
            json!({
                "decision": d.decision,
                "category": d.category,
                "message": d.message,
                "scope": d.scope,
                "op": d.op,
            })
        }
        "parse" => {
            let mut budget = MAX_COMMANDS;
            match parse_script(&text(req, "text"), &mut budget) {
                Ok(c) => json!({"commands": commands_json(&c)}),
                Err(PErr::Parse) => json!({"error": "parse"}),
                Err(PErr::TooComplex) => json!({"error": "too_complex"}),
            }
        }
        "fallback_split" => match fallback_split(&text(req, "text"), None) {
            Ok(c) => json!({"commands": commands_json(&c)}),
            Err(_) => json!({"error": "too_complex"}),
        },
        "strip_heredoc_bodies" => json!({"text": strip_heredoc_bodies(&text(req, "text"))}),
        "body_substitutions" => {
            let body: Vec<char> = text(req, "text").chars().collect();
            let subs: Vec<String> = body_substitutions(&body)
                .iter()
                .map(|s| s.iter().collect())
                .collect();
            json!({"subs": subs})
        }
        "redact" => json!({"text": redact(&text(req, "text"))}),
        "redact_for_log" => json!({"text": redact_for_log(&text(req, "text"))}),
        "load_policy" => match load_policy(req.get("path").and_then(|p| p.as_str())) {
            Ok(m) => json!({"modes": m}),
            Err(e) => json!({"crash": e.0}),
        },
        "probe_git_state" => git_state_json(&probe_git_state(&text(req, "cwd"))),
        "installer_problem" => {
            json!({"text": installer_problem(&text(req, "cwd"), &text(req, "home"))})
        }
        _ => json!({"error": format!("unknown kind {:?}", kind)}),
    }
}

pub fn run() -> i32 {
    let stdin = std::io::stdin();
    let mut stdout = std::io::stdout();
    for line in stdin.lock().lines() {
        let Ok(line) = line else { break };
        if line.trim().is_empty() {
            continue;
        }
        let req: Value = match serde_json::from_str(&line) {
            Ok(v) => v,
            Err(e) => {
                let _ = writeln!(
                    stdout,
                    "{}",
                    json!({"error": format!("bad request: {}", e)})
                );
                continue;
            }
        };
        // Each request on its own: fresh caches, and the installer check
        // replaced only when the request says so (the Python tests patch it).
        clear_caches();
        let override_ = req
            .get("installer_problem")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());
        INSTALLER_PROBLEM_OVERRIDE.with(|o| *o.borrow_mut() = override_);
        let answer = match catch_unwind(AssertUnwindSafe(|| handle(&req))) {
            Ok(v) => v,
            Err(err) => json!({"panic": crate::hook::panic_repr(err.as_ref())}),
        };
        let _ = writeln!(stdout, "{}", answer);
        let _ = stdout.flush();
    }
    0
}
