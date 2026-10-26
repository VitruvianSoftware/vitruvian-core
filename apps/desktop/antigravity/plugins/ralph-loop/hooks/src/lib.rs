// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

use serde_json::{json, Map, Value};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

pub const MIN_ITERATIONS: i64 = 1;
pub const MAX_ITERATIONS_LIMIT: i64 = 200;
pub const DEFAULT_MAX_ITERATIONS: i64 = 10;

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

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

fn non_empty_string_field(obj: &Map<String, Value>, key: &str) -> Option<String> {
    match obj.get(key) {
        Some(Value::String(s)) if !s.is_empty() => Some(s.clone()),
        _ => None,
    }
}

fn value_as_i64(val: Option<&Value>, default: i64) -> i64 {
    match val {
        Some(Value::Number(n)) => n
            .as_i64()
            .or_else(|| n.as_f64().map(|f| f as i64))
            .filter(|&v| v != 0)
            .unwrap_or(default),
        Some(Value::String(s)) => s
            .trim()
            .parse::<i64>()
            .ok()
            .filter(|&v| v != 0)
            .unwrap_or(default),
        _ => default,
    }
}

fn extract_transcript_assistant_message(transcript_path: &Path) -> Option<String> {
    let content = fs::read_to_string(transcript_path).ok()?;
    let trimmed = content.trim();
    if trimmed.is_empty() {
        return None;
    }
    for line in trimmed.split('\n').rev() {
        let Ok(entry) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        let Some(obj) = entry.as_object() else {
            continue;
        };
        let role = non_empty_string_field(obj, "role")
            .or_else(|| non_empty_string_field(obj, "type"))
            .or_else(|| non_empty_string_field(obj, "source"));
        if matches!(
            role.as_deref(),
            Some("assistant" | "MODEL" | "PLANNER_RESPONSE")
        ) {
            if let Some(Value::String(s)) = obj.get("content") {
                return Some(s.clone());
            }
            return serde_json::to_string(&entry).ok();
        }
    }
    None
}

fn save_state_atomic(state_file: &Path, next: &Map<String, Value>) {
    let Ok(serialized) = serde_json::to_string_pretty(&Value::Object(next.clone())) else {
        return;
    };
    let tmp = state_file.with_extension("json.tmp");
    if fs::write(&tmp, serialized).is_ok() {
        let _ = fs::rename(&tmp, state_file);
    }
}

/// Evaluates the Stop hook payload and updates the loop state file if present.
/// Always returns a JSON string (`"{}"` or `{"decision":"continue","reason":"..."}`).
pub fn handle_stop_payload(payload: &str, state_dir: Option<&Path>) -> String {
    let Some(state_dir) = state_dir else {
        return "{}".to_string();
    };
    let raw = if payload.trim().is_empty() {
        "{}"
    } else {
        payload
    };
    let Ok(Value::Object(event)) = serde_json::from_str::<Value>(raw) else {
        return "{}".to_string();
    };

    let conv_id = non_empty_string_field(&event, "conversationId")
        .or_else(|| non_empty_string_field(&event, "session_id"))
        .unwrap_or_default()
        .trim()
        .to_string();

    if conv_id.is_empty() || conv_id.contains('/') || conv_id.contains('\\') {
        return "{}".to_string();
    }

    let state_file = state_dir.join(format!("{conv_id}.json"));
    if !state_file.exists() {
        return "{}".to_string();
    }

    let Ok(state_raw) = fs::read_to_string(&state_file) else {
        return "{}".to_string();
    };
    let Ok(Value::Object(mut state)) = serde_json::from_str::<Value>(&state_raw) else {
        return "{}".to_string();
    };

    if state.get("active") != Some(&Value::Bool(true)) {
        return "{}".to_string();
    }

    let promise_raw =
        non_empty_string_field(&state, "completionPromise").unwrap_or_else(|| "DONE".to_string());
    let promise_text = promise_raw.trim().to_string();
    let tag = format!("<promise>{promise_text}</promise>");

    let mut last_assistant_text = non_empty_string_field(&event, "lastAssistantMessage")
        .or_else(|| non_empty_string_field(&event, "response"))
        .unwrap_or_default();

    let transcript_path = non_empty_string_field(&event, "transcriptPath")
        .or_else(|| non_empty_string_field(&event, "transcript_path"));
    if let Some(tp) = transcript_path {
        let p = Path::new(&tp);
        if p.exists() {
            if let Some(extracted) = extract_transcript_assistant_message(p) {
                last_assistant_text = extracted;
            }
        }
    }

    let now = now_millis();

    if last_assistant_text.contains(&tag) {
        state.insert("active".to_string(), Value::Bool(false));
        state.insert("status".to_string(), Value::String("completed".to_string()));
        state.insert("completedAt".to_string(), json!(now));
        state.insert("updatedAt".to_string(), json!(now));
        save_state_atomic(&state_file, &state);
        return "{}".to_string();
    }

    let iteration = value_as_i64(state.get("iteration"), 0);
    let max_iterations = value_as_i64(state.get("maxIterations"), DEFAULT_MAX_ITERATIONS);

    if iteration >= max_iterations {
        state.insert("active".to_string(), Value::Bool(false));
        state.insert(
            "status".to_string(),
            Value::String("max_iterations".to_string()),
        );
        state.insert("completedAt".to_string(), json!(now));
        state.insert("updatedAt".to_string(), json!(now));
        save_state_atomic(&state_file, &state);
        return "{}".to_string();
    }

    let next_iteration = iteration + 1;
    state.insert("iteration".to_string(), json!(next_iteration));
    state.insert("status".to_string(), Value::String("running".to_string()));
    state.insert("updatedAt".to_string(), json!(now));
    save_state_atomic(&state_file, &state);

    let task_hint = match non_empty_string_field(&state, "prompt") {
        Some(p) => format!(" Task: {p}"),
        None => String::new(),
    };
    let reason = format!(
        "Ralph Loop (iteration {next_iteration}/{max_iterations}): continue working on the task until completion criteria are met and emit <promise>{promise_text}</promise>.{task_hint}"
    );

    serde_json::to_string(&json!({
        "decision": "continue",
        "reason": reason,
    }))
    .unwrap_or_else(|_| "{}".to_string())
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

    #[test]
    fn promise_matching_works() {
        assert!(check_promise_matched(
            "All checks pass! <promise>DONE</promise>",
            "DONE"
        ));
        assert!(!check_promise_matched("Still working...", "DONE"));
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
        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["decision"], "continue");
        assert_eq!(
            parsed["reason"],
            "Ralph Loop (iteration 2/5): continue working on the task until completion criteria are met and emit <promise>ALL_GREEN</promise>. Task: Fix tests"
        );

        let updated: Value =
            serde_json::from_str(&fs::read_to_string(&state_file).unwrap()).unwrap();
        assert_eq!(updated["iteration"], 2);
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

        let payload = serde_json::to_string(&json!({
            "conversationId": "conv-2",
            "transcriptPath": transcript_file.to_str().unwrap()
        }))
        .unwrap();
        let out = handle_stop_payload(&payload, Some(&dir));
        assert_eq!(out, "{}");

        let updated: Value =
            serde_json::from_str(&fs::read_to_string(&state_file).unwrap()).unwrap();
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

        let updated: Value =
            serde_json::from_str(&fs::read_to_string(&state_file).unwrap()).unwrap();
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
}
