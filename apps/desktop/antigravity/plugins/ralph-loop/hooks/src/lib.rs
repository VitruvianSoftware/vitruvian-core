// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

//! The ralph-loop `Stop` hook.
//!
//! When the conversation has an active loop in
//! `ralph-loop-state/<conversationId>.json`, the turn is bounced back
//! (`{"decision":"continue"}`) until the reply contains
//! `<promise>COMPLETION_PROMISE</promise>` or `maxIterations` is reached.
//!
//! The crate uses only the standard library, so `../rust-hook.sh` can build it
//! with a bare `rustc` wherever the plugin is installed. It replaced a Node.js
//! script, and reads odd input the way that script did (see the `js_*`
//! helpers).

pub mod json;

use json::{obj, Map, Value};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

pub const MIN_ITERATIONS: i64 = 1;
pub const MAX_ITERATIONS_LIMIT: i64 = 200;
pub const DEFAULT_MAX_ITERATIONS: i64 = 10;

fn now_millis() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as f64)
        .unwrap_or(0.0)
}

// ---- JavaScript coercions -------------------------------------------------

/// `String(v)`.
fn js_string(v: &Value) -> String {
    match v {
        Value::Null => "null".to_string(),
        Value::Bool(b) => b.to_string(),
        Value::Number(_) => v.to_string(),
        Value::String(s) => s.clone(),
        Value::Array(a) => a
            .iter()
            .map(|x| {
                if x.is_null() {
                    String::new()
                } else {
                    js_string(x)
                }
            })
            .collect::<Vec<_>>()
            .join(","),
        Value::Object(_) => "[object Object]".to_string(),
    }
}

/// JavaScript truthiness.
fn js_truthy(v: Option<&Value>) -> bool {
    match v {
        None | Some(Value::Null) => false,
        Some(Value::Bool(b)) => *b,
        Some(Value::Number(n)) => *n != 0.0 && !n.is_nan(),
        Some(Value::String(s)) => !s.is_empty(),
        Some(_) => true,
    }
}

/// `a || b`: the first truthy of the two members, else `None`.
fn js_or<'a>(m: &'a Map, a: &str, b: &str) -> Option<&'a Value> {
    if js_truthy(m.get(a)) {
        m.get(a)
    } else if js_truthy(m.get(b)) {
        m.get(b)
    } else {
        None
    }
}

/// `String.prototype.trim`.
fn js_trim(s: &str) -> &str {
    s.trim_matches(|c: char| c.is_whitespace() || c == '\u{FEFF}')
}

/// `Number(v)`.
fn js_number(v: Option<&Value>) -> f64 {
    match v {
        None => f64::NAN,
        Some(Value::Null) => 0.0,
        Some(Value::Bool(b)) => f64::from(u8::from(*b)),
        Some(Value::Number(n)) => *n,
        Some(Value::String(s)) => js_string_to_number(s),
        Some(Value::Array(a)) if a.is_empty() => 0.0,
        Some(Value::Array(a)) if a.len() == 1 => js_number(Some(&a[0])),
        Some(_) => f64::NAN,
    }
}

/// JavaScript's StringToNumber: trimmed; empty is 0; `0x`/`0o`/`0b`
/// prefixes (unsigned) read in base 16/8/2; `Infinity` with an optional
/// sign; otherwise a plain decimal literal. Rust's own parser also takes
/// "inf", "nan" and "infinity", which JavaScript reads as NaN.
fn js_string_to_number(s: &str) -> f64 {
    let t = js_trim(s);
    if t.is_empty() {
        return 0.0;
    }
    let lower = t.get(..2).map(str::to_ascii_lowercase);
    let radix = match lower.as_deref() {
        Some("0x") => 16,
        Some("0o") => 8,
        Some("0b") => 2,
        _ => 0,
    };
    if radix != 0 {
        let digits = &t[2..];
        if digits.is_empty() || !digits.chars().all(|c| c.is_digit(radix)) {
            return f64::NAN;
        }
        return digits.chars().fold(0.0, |n, c| {
            n * f64::from(radix) + f64::from(c.to_digit(radix).unwrap())
        });
    }
    match t {
        "Infinity" | "+Infinity" => return f64::INFINITY,
        "-Infinity" => return f64::NEG_INFINITY,
        _ => {}
    }
    let body = t.strip_prefix(['+', '-']).unwrap_or(t);
    let decimal = !body.is_empty()
        && body
            .chars()
            .all(|c| c.is_ascii_digit() || matches!(c, '.' | 'e' | 'E' | '+' | '-'))
        && body.starts_with(|c: char| c.is_ascii_digit() || c == '.');
    if decimal {
        t.parse::<f64>().unwrap_or(f64::NAN)
    } else {
        f64::NAN
    }
}

/// `Number(v) || fallback`.
fn js_number_or(v: Option<&Value>, fallback: f64) -> f64 {
    let n = js_number(v);
    if n == 0.0 || n.is_nan() {
        fallback
    } else {
        n
    }
}

/// A number as JavaScript prints it in a template literal.
fn js_num_text(n: f64) -> String {
    Value::Number(n).to_string()
}

// ---- The hook ---------------------------------------------------------------

/// Checks whether an assistant message contains `<promise>${completionPromise}</promise>`.
pub fn check_promise_matched(text: &str, completion_promise: &str) -> bool {
    let token = completion_promise.trim();
    let token = if token.is_empty() { "DONE" } else { token };
    let tag = format!("<promise>{token}</promise>");
    text.contains(&tag)
}

/// Resolves the `ralph-loop-state` directory from `ANTIGRAVITY_APP_DATA_DIR` or `HOME`.
pub fn resolve_state_dir(app_data_dir: Option<&str>, home_dir: Option<&str>) -> Option<PathBuf> {
    if let Some(dir) = app_data_dir.filter(|s| !s.is_empty()) {
        return Some(Path::new(dir).join("ralph-loop-state"));
    }
    let home = home_dir.filter(|s| !s.is_empty())?;
    Some(
        Path::new(home)
            .join(".gemini")
            .join("antigravity")
            .join("ralph-loop-state"),
    )
}

/// The latest assistant turn in a transcript: its `content` if that is a
/// string, else the whole entry as JSON. Lines that are not JSON are skipped.
fn extract_transcript_assistant_message(transcript_path: &Path) -> Option<String> {
    let content = fs::read_to_string(transcript_path).ok()?;
    for line in js_trim(&content).split('\n').rev() {
        let Ok(entry) = json::parse(line) else {
            continue;
        };
        let Some(m) = entry.as_object() else {
            continue;
        };
        // `entry.role || entry.type || entry.source`, compared as-is.
        let role = [m.get("role"), m.get("type"), m.get("source")]
            .into_iter()
            .find(|v| js_truthy(*v))
            .flatten();
        if matches!(
            role.and_then(Value::as_str),
            Some("assistant" | "MODEL" | "PLANNER_RESPONSE")
        ) {
            return Some(match m.get("content") {
                Some(Value::String(s)) => s.clone(),
                _ => entry.to_string(),
            });
        }
    }
    None
}

/// Writes the state through `<file>.tmp` and a rename, like the script did.
fn save_state_atomic(state_file: &Path, next: &Map) {
    let mut tmp = state_file.as_os_str().to_owned();
    tmp.push(".tmp");
    let tmp = PathBuf::from(tmp);
    if fs::write(&tmp, Value::Object(next.clone()).to_string_pretty()).is_ok() {
        let _ = fs::rename(&tmp, state_file);
    }
}

/// Evaluates the Stop hook payload and updates the loop state file if present.
/// Always returns a JSON string (`"{}"` or `{"decision":"continue","reason":"..."}`).
pub fn handle_stop_payload(payload: &str, state_dir: Option<&Path>) -> String {
    handle_stop_payload_at(payload, state_dir, now_millis())
}

fn handle_stop_payload_at(payload: &str, state_dir: Option<&Path>, now: f64) -> String {
    let empty = "{}".to_string();
    let Some(state_dir) = state_dir else {
        return empty;
    };
    let raw = if payload.trim().is_empty() {
        "{}"
    } else {
        payload
    };
    // JSON that is not an object has no conversationId: nothing to do.
    let Some(event) = json::parse(raw).ok().and_then(|v| v.as_object().cloned()) else {
        return empty;
    };

    let conv_id = js_or(&event, "conversationId", "session_id")
        .map(js_string)
        .unwrap_or_default();
    let conv_id = js_trim(&conv_id);
    if conv_id.is_empty() || conv_id.contains('/') || conv_id.contains('\\') {
        return empty;
    }

    let state_file = state_dir.join(format!("{conv_id}.json"));
    let Some(mut state) = fs::read_to_string(&state_file)
        .ok()
        .and_then(|raw| json::parse_object(&raw))
    else {
        return empty;
    };

    if state.get("active") != Some(&Value::Bool(true)) {
        return empty;
    }

    // `String(state.completionPromise || "DONE").trim()`
    let promise_text = js_or(&state, "completionPromise", "")
        .map(js_string)
        .unwrap_or_else(|| "DONE".to_string());
    let promise_text = js_trim(&promise_text).to_string();
    let tag = format!("<promise>{promise_text}</promise>");

    let mut last_assistant_text = js_or(&event, "lastAssistantMessage", "response")
        .map(js_string)
        .unwrap_or_default();

    // `event.transcriptPath || event.transcript_path`, used only if a string.
    if let Some(Value::String(tp)) = js_or(&event, "transcriptPath", "transcript_path") {
        let p = Path::new(tp);
        if p.exists() {
            if let Some(extracted) = extract_transcript_assistant_message(p) {
                last_assistant_text = extracted;
            }
        }
    }

    if last_assistant_text.contains(&tag) {
        state.insert("active", false);
        state.insert("status", "completed");
        state.insert("completedAt", now);
        state.insert("updatedAt", now);
        save_state_atomic(&state_file, &state);
        return empty;
    }

    let iteration = js_number_or(state.get("iteration"), 0.0);
    let max_iterations = js_number_or(state.get("maxIterations"), DEFAULT_MAX_ITERATIONS as f64);

    if iteration >= max_iterations {
        state.insert("active", false);
        state.insert("status", "max_iterations");
        state.insert("completedAt", now);
        state.insert("updatedAt", now);
        save_state_atomic(&state_file, &state);
        return empty;
    }

    let next_iteration = iteration + 1.0;
    state.insert("iteration", next_iteration);
    state.insert("status", "running");
    state.insert("updatedAt", now);
    save_state_atomic(&state_file, &state);

    let task_hint = if js_truthy(state.get("prompt")) {
        format!(" Task: {}", js_string(&state["prompt"]))
    } else {
        String::new()
    };
    let reason = format!(
        "Ralph Loop (iteration {}/{}): continue working on the task until completion criteria are met and emit <promise>{promise_text}</promise>.{task_hint}",
        js_num_text(next_iteration),
        js_num_text(max_iterations),
    );

    obj([
        ("decision", Value::from("continue")),
        ("reason", Value::from(reason)),
    ])
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::process;
    use std::sync::atomic::{AtomicU64, Ordering};

    static TEST_COUNTER: AtomicU64 = AtomicU64::new(0);

    fn temp_state_dir() -> PathBuf {
        let id = TEST_COUNTER.fetch_add(1, Ordering::SeqCst);
        let dir = std::env::temp_dir().join(format!("ralph-loop-test-{}-{}", process::id(), id));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn read_state(path: &Path) -> Value {
        json::parse(&fs::read_to_string(path).unwrap()).unwrap()
    }

    /// One Stop event against a state file holding `state`; returns the
    /// hook's answer and the state it saved.
    fn stop(state: &str, event: &str) -> (String, Value) {
        let dir = temp_state_dir();
        let state_file = dir.join("c.json");
        fs::write(&state_file, state).unwrap();
        let out = handle_stop_payload_at(event, Some(&dir), 5.0);
        let saved = read_state(&state_file);
        let _ = fs::remove_dir_all(&dir);
        (out, saved)
    }

    #[test]
    fn promise_matching_works() {
        assert!(check_promise_matched(
            "All checks pass! <promise>DONE</promise>",
            "DONE"
        ));
        assert!(!check_promise_matched("Still working...", "DONE"));
        assert!(!check_promise_matched("Still working on DONE...", "DONE"));
        assert!(check_promise_matched(
            "Finished <promise>SHIP_IT</promise>",
            "SHIP_IT"
        ));
    }

    #[test]
    fn continues_active_loop_and_increments_iteration() {
        let dir = temp_state_dir();
        let state_file = dir.join("conv-1.json");
        fs::write(
            &state_file,
            r#"{"conversationId":"conv-1","prompt":"Fix tests","completionPromise":"ALL_GREEN","iteration":1,"maxIterations":5,"active":true,"status":"running"}"#,
        )
        .unwrap();

        let out = handle_stop_payload(
            r#"{"conversationId":"conv-1","lastAssistantMessage":"Working on step 2"}"#,
            Some(&dir),
        );
        let parsed = json::parse(&out).unwrap();
        assert_eq!(parsed["decision"], "continue");
        assert_eq!(
            parsed["reason"],
            "Ralph Loop (iteration 2/5): continue working on the task until completion criteria are met and emit <promise>ALL_GREEN</promise>. Task: Fix tests"
        );

        let updated = read_state(&state_file);
        assert_eq!(updated["iteration"], 2.0);
        assert_eq!(updated["active"], true);
        assert_eq!(updated["status"], "running");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn completes_when_promise_emitted_in_transcript() {
        let dir = temp_state_dir();
        let state_file = dir.join("conv-2.json");
        let transcript_file = dir.join("transcript.jsonl");
        fs::write(
            &state_file,
            r#"{"conversationId":"conv-2","completionPromise":"DONE","iteration":2,"maxIterations":5,"active":true,"status":"running"}"#,
        )
        .unwrap();
        fs::write(
            &transcript_file,
            "{\"role\":\"user\",\"content\":\"go\"}\n{\"role\":\"assistant\",\"content\":\"Done <promise>DONE</promise>\"}\n",
        )
        .unwrap();

        let payload = obj([
            ("conversationId", Value::from("conv-2")),
            (
                "transcriptPath",
                Value::from(transcript_file.to_str().unwrap()),
            ),
        ])
        .to_string();
        let out = handle_stop_payload(&payload, Some(&dir));
        assert_eq!(out, "{}");

        let updated = read_state(&state_file);
        assert_eq!(updated["active"], false);
        assert_eq!(updated["status"], "completed");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn stops_at_max_iterations() {
        let dir = temp_state_dir();
        let state_file = dir.join("conv-3.json");
        fs::write(
            &state_file,
            r#"{"conversationId":"conv-3","completionPromise":"DONE","iteration":3,"maxIterations":3,"active":true,"status":"running"}"#,
        )
        .unwrap();

        let out = handle_stop_payload(
            r#"{"conversationId":"conv-3","lastAssistantMessage":"Still working"}"#,
            Some(&dir),
        );
        assert_eq!(out, "{}");

        let updated = read_state(&state_file);
        assert_eq!(updated["active"], false);
        assert_eq!(updated["status"], "max_iterations");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn rejects_path_traversal_conversation_id() {
        let dir = temp_state_dir();
        let out = handle_stop_payload(r#"{"conversationId":"../secret"}"#, Some(&dir));
        assert_eq!(out, "{}");
        let _ = fs::remove_dir_all(&dir);
    }

    // ---- Ported from the JavaScript suite (core.test.mjs, evaluateStopEvent) --

    #[test]
    fn loop_runs_to_max_then_stops_and_a_promise_completes_it() {
        let dir = temp_state_dir();
        let f = dir.join("conv-42.json");
        fs::write(
            &f,
            r#"{"conversationId":"conv-42","prompt":"Implement feature X","completionPromise":"FEATURE_X_READY","iteration":0,"maxIterations":2,"active":true,"status":"running"}"#,
        )
        .unwrap();
        let ev = |msg: &str| {
            obj([
                ("conversationId", Value::from("conv-42")),
                ("lastAssistantMessage", Value::from(msg)),
            ])
            .to_string()
        };
        let step1 = json::parse(&handle_stop_payload(&ev("step 1"), Some(&dir))).unwrap();
        assert!(step1["reason"]
            .as_str()
            .unwrap()
            .starts_with("Ralph Loop (iteration 1/2): continue working on the task until completion criteria are met and emit <promise>FEATURE_X_READY</promise>."));
        assert_eq!(read_state(&f)["iteration"], 1.0);
        let step2 = json::parse(&handle_stop_payload(&ev("step 2"), Some(&dir))).unwrap();
        assert!(step2["reason"].as_str().unwrap().contains("iteration 2/2"));
        assert_eq!(handle_stop_payload(&ev("step 3"), Some(&dir)), "{}");
        assert_eq!(read_state(&f)["status"], "max_iterations");
        assert_eq!(read_state(&f)["active"], false);

        fs::write(
            &f,
            r#"{"conversationId":"conv-42","completionPromise":"DONE","maxIterations":5,"active":true}"#,
        )
        .unwrap();
        assert_eq!(
            handle_stop_payload(&ev("Verified. <promise>DONE</promise>"), Some(&dir)),
            "{}"
        );
        assert_eq!(read_state(&f)["status"], "completed");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn inactive_or_missing_state_is_left_alone() {
        let (out, saved) = stop(
            r#"{"active":false,"iteration":1}"#,
            r#"{"conversationId":"c"}"#,
        );
        assert_eq!(out, "{}");
        assert_eq!(saved.to_string(), r#"{"active":false,"iteration":1}"#);
        let (out, _) = stop(r#"{"active":"true"}"#, r#"{"conversationId":"c"}"#);
        assert_eq!(out, "{}");
        let dir = temp_state_dir();
        assert_eq!(
            handle_stop_payload(r#"{"conversationId":"nope"}"#, Some(&dir)),
            "{}"
        );
        assert_eq!(handle_stop_payload("[1]", Some(&dir)), "{}");
        assert_eq!(handle_stop_payload("not json", Some(&dir)), "{}");
        assert!(fs::read_dir(&dir).unwrap().next().is_none());
        let _ = fs::remove_dir_all(&dir);
    }

    // ---- Parity with the Node.js script the hook replaced -------------------

    #[test]
    fn strings_become_numbers_as_javascript_number_reads_them() {
        let cases = [
            ("0x10", 16.0),
            ("0X1f", 31.0),
            ("0b11", 3.0),
            ("0o17", 15.0),
            ("  12  ", 12.0),
            ("", 0.0),
            ("1e3", 1000.0),
            (".5", 0.5),
            ("5.", 5.0),
            ("+7", 7.0),
            ("-Infinity", f64::NEG_INFINITY),
        ];
        for (s, want) in cases {
            assert_eq!(js_string_to_number(s), want, "{s:?}");
        }
        for s in [
            "inf", "nan", "infinity", "0x", "-0x10", "0b2", "1_000", "12px", "e5", "0x1g",
        ] {
            assert!(js_string_to_number(s).is_nan(), "{s:?}");
        }
        // Through the hook: a hex maximum is read as JavaScript reads it.
        let (out, _) = stop(
            r#"{"active":true,"iteration":3,"maxIterations":"0x10"}"#,
            r#"{"conversationId":"c"}"#,
        );
        assert!(out.contains("(iteration 4/16)"), "{out}");
    }

    #[test]
    fn numbers_are_read_the_way_javascript_does() {
        // Number(x) || default: "3" is 3, true is 1, "abc" and 0 fall back.
        let (out, saved) = stop(
            r#"{"active":true,"iteration":"1","maxIterations":true}"#,
            r#"{"conversationId":"c"}"#,
        );
        assert_eq!(out, "{}", "1 >= 1 stops");
        assert_eq!(saved["status"], "max_iterations");

        let (out, saved) = stop(
            r#"{"active":true,"iteration":"abc","maxIterations":0}"#,
            r#"{"conversationId":"c"}"#,
        );
        assert!(out.contains("(iteration 1/10)"), "{out}");
        assert_eq!(saved["iteration"], 1.0);

        // A fractional iteration counts on as JavaScript would.
        let (out, _) = stop(
            r#"{"active":true,"iteration":1.5,"maxIterations":4}"#,
            r#"{"conversationId":"c"}"#,
        );
        assert!(out.contains("(iteration 2.5/4)"), "{out}");

        // A negative maximum is truthy: the loop stops at once.
        let (out, _) = stop(
            r#"{"active":true,"maxIterations":-1}"#,
            r#"{"conversationId":"c"}"#,
        );
        assert_eq!(out, "{}");
    }

    #[test]
    fn non_string_ids_promises_and_prompts_are_stringified() {
        let dir = temp_state_dir();
        fs::write(
            dir.join("123.json"),
            r#"{"active":true,"completionPromise":42,"prompt":7}"#,
        )
        .unwrap();
        let out = handle_stop_payload_at(r#"{"conversationId":123}"#, Some(&dir), 1.0);
        assert!(out.contains("<promise>42</promise>. Task: 7"), "{out}");
        let done = handle_stop_payload_at(
            r#"{"session_id":123,"response":"<promise>42</promise>"}"#,
            Some(&dir),
            1.0,
        );
        assert_eq!(done, "{}");
        assert_eq!(read_state(&dir.join("123.json"))["status"], "completed");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_whitespace_promise_is_the_empty_tag() {
        // String("  " || "DONE").trim() is "": the tag is <promise></promise>.
        let (out, saved) = stop(
            r#"{"active":true,"completionPromise":"  "}"#,
            r#"{"conversationId":"c","lastAssistantMessage":"x <promise></promise>"}"#,
        );
        assert_eq!(out, "{}");
        assert_eq!(saved["status"], "completed");
    }

    #[test]
    fn transcript_entry_without_string_content_is_matched_as_json_in_key_order() {
        let dir = temp_state_dir();
        fs::write(dir.join("c.json"), r#"{"active":true}"#).unwrap();
        let t = dir.join("t.jsonl");
        // The tag is only in another key; JSON.stringify keeps key order.
        fs::write(
            &t,
            "{\"type\":\"MODEL\",\"z\":\"<promise>DONE</promise>\",\"content\":{\"a\":1}}\nnot json\n",
        )
        .unwrap();
        let ev = obj([
            ("conversationId", Value::from("c")),
            ("transcriptPath", Value::from(t.to_str().unwrap())),
        ])
        .to_string();
        assert_eq!(handle_stop_payload(&ev, Some(&dir)), "{}");
        assert_eq!(read_state(&dir.join("c.json"))["status"], "completed");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_non_string_role_hides_type_like_the_script() {
        // `entry.role || entry.type`: role 5 is truthy, so type is not read.
        let dir = temp_state_dir();
        fs::write(dir.join("c.json"), r#"{"active":true}"#).unwrap();
        let t = dir.join("t.jsonl");
        fs::write(
            &t,
            "{\"role\":5,\"type\":\"MODEL\",\"content\":\"<promise>DONE</promise>\"}\n",
        )
        .unwrap();
        let ev = obj([
            ("conversationId", Value::from("c")),
            ("transcriptPath", Value::from(t.to_str().unwrap())),
        ])
        .to_string();
        assert!(handle_stop_payload(&ev, Some(&dir)).contains("continue"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_non_string_transcript_path_does_not_fall_back() {
        // `transcriptPath || transcript_path`: 5 wins, and is not a string.
        let dir = temp_state_dir();
        fs::write(dir.join("c.json"), r#"{"active":true}"#).unwrap();
        let t = dir.join("t.jsonl");
        fs::write(
            &t,
            "{\"role\":\"assistant\",\"content\":\"<promise>DONE</promise>\"}\n",
        )
        .unwrap();
        let ev = obj([
            ("conversationId", Value::from("c")),
            ("transcriptPath", Value::from(5)),
            ("transcript_path", Value::from(t.to_str().unwrap())),
        ])
        .to_string();
        assert!(handle_stop_payload(&ev, Some(&dir)).contains("continue"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn saved_state_keeps_key_order_and_is_pretty_printed_without_newline() {
        let dir = temp_state_dir();
        let f = dir.join("c.json");
        fs::write(&f, r#"{"zeta":1,"active":true,"alpha":2}"#).unwrap();
        handle_stop_payload_at(r#"{"conversationId":"c"}"#, Some(&dir), 9.0);
        assert_eq!(
            fs::read_to_string(&f).unwrap(),
            "{\n  \"zeta\": 1,\n  \"active\": true,\n  \"alpha\": 2,\n  \"iteration\": 1,\n  \"status\": \"running\",\n  \"updatedAt\": 9\n}"
        );
        assert!(!dir.join("c.json.tmp").exists());
        let _ = fs::remove_dir_all(&dir);
    }
}
