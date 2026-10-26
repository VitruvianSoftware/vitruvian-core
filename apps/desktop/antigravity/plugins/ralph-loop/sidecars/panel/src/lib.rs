// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

pub mod openui;

use serde_json::{json, Value};

pub const MIN_ITERATIONS: i64 = 1;
pub const MAX_ITERATIONS_LIMIT: i64 = 200;
pub const DEFAULT_MAX_ITERATIONS: i64 = 10;

pub fn check_promise_matched(text: &str, promise_text: &str) -> bool {
    let target = promise_text.trim();
    if target.is_empty() {
        return false;
    }
    if text.is_empty() {
        return false;
    }

    let lower = text.to_ascii_lowercase();
    let mut search_from = 0;
    while let Some(open_rel) = lower[search_from..].find("<promise>") {
        let open_end = search_from + open_rel + "<promise>".len();
        if let Some(close_rel) = lower[open_end..].find("</promise>") {
            let inner = text[open_end..open_end + close_rel].trim();
            if inner == target {
                return true;
            }
            search_from = open_end + close_rel + "</promise>".len();
        } else {
            break;
        }
    }

    text.contains(target)
}

pub fn create_loop_state(params: &Value) -> Result<Value, String> {
    let id = params
        .get("id")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .unwrap_or("");
    let prompt = params
        .get("prompt")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .unwrap_or("");

    if id.is_empty() {
        return Err("Loop id is required".to_string());
    }
    if prompt.is_empty() {
        return Err("Loop prompt is required".to_string());
    }

    let max_raw = params
        .get("maxIterations")
        .and_then(|v| v.as_i64().or_else(|| v.as_str()?.parse::<i64>().ok()))
        .unwrap_or(DEFAULT_MAX_ITERATIONS);
    let max_iterations = max_raw.clamp(MIN_ITERATIONS, MAX_ITERATIONS_LIMIT);

    let completion_promise = params
        .get("completionPromise")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .unwrap_or("");
    let verification_command = params
        .get("verificationCommand")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .unwrap_or("");
    let workspace_path = params
        .get("workspacePath")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .unwrap_or("");
    let now = params.get("now").and_then(|v| v.as_i64()).unwrap_or(0);

    Ok(json!({
        "id": id,
        "prompt": prompt,
        "completionPromise": completion_promise,
        "verificationCommand": verification_command,
        "workspacePath": workspace_path,
        "iteration": 0,
        "maxIterations": max_iterations,
        "status": "active",
        "startedAt": now,
        "updatedAt": now,
        "completedAt": null,
        "history": [],
    }))
}

pub fn update_loop_iteration(loop_val: &Value, params: &Value) -> Value {
    let Some(obj) = loop_val.as_object() else {
        return loop_val.clone();
    };
    let status = obj.get("status").and_then(|v| v.as_str()).unwrap_or("");
    if status != "active" {
        return loop_val.clone();
    }

    let last_output = params
        .get("lastOutput")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let verification_passed = params.get("verificationPassed").and_then(|v| v.as_bool());
    let verification_output = params
        .get("verificationOutput")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let now = params.get("now").and_then(|v| v.as_i64()).unwrap_or(0);

    let prev_iter = obj.get("iteration").and_then(|v| v.as_i64()).unwrap_or(0);
    let next_iter = prev_iter + 1;
    let max_iter = obj
        .get("maxIterations")
        .and_then(|v| v.as_i64())
        .unwrap_or(DEFAULT_MAX_ITERATIONS);
    let completion_promise = obj
        .get("completionPromise")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    let promise_matched = if !completion_promise.is_empty() {
        check_promise_matched(last_output, completion_promise)
    } else {
        verification_passed == Some(true)
    };
    let verify_ok = verification_passed != Some(false);
    let is_complete = promise_matched && verify_ok;
    let is_capped = !is_complete && next_iter >= max_iter;

    let next_status = if is_complete {
        "completed"
    } else if is_capped {
        "capped"
    } else {
        "active"
    };

    let output_excerpt: String = last_output.trim().chars().take(280).collect();
    let ver_excerpt: String = verification_output.trim().chars().take(280).collect();
    let entry = json!({
        "iteration": next_iter,
        "timestamp": now,
        "promiseMatched": promise_matched,
        "verificationPassed": verification_passed,
        "outputExcerpt": output_excerpt,
        "verificationExcerpt": ver_excerpt,
    });

    let mut history = obj
        .get("history")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    history.push(entry);
    if history.len() > 50 {
        let skip = history.len() - 50;
        history.drain(0..skip);
    }

    let mut updated = obj.clone();
    updated.insert("iteration".to_string(), json!(next_iter));
    updated.insert("status".to_string(), json!(next_status));
    updated.insert("updatedAt".to_string(), json!(now));
    if next_status != "active" {
        updated.insert("completedAt".to_string(), json!(now));
    }
    updated.insert("history".to_string(), Value::Array(history));
    Value::Object(updated)
}

pub fn evaluate_stop_event(loop_val: Option<&Value>, payload: &Value) -> Value {
    let Some(lp) = loop_val else {
        return json!({
            "decision": "allow",
            "reason": "",
            "updatedLoop": null,
        });
    };
    if lp.get("status").and_then(|v| v.as_str()) != Some("active") {
        return json!({
            "decision": "allow",
            "reason": "",
            "updatedLoop": lp,
        });
    }

    let last_text = payload
        .get("lastAssistantMessage")
        .or_else(|| payload.get("transcript"))
        .or_else(|| payload.get("reason"))
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let verification_passed = payload.get("verificationPassed").and_then(|v| v.as_bool());
    let verification_output = payload
        .get("verificationOutput")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let now = payload.get("now").and_then(|v| v.as_i64()).unwrap_or(0);

    let updated = update_loop_iteration(
        lp,
        &json!({
            "lastOutput": last_text,
            "verificationPassed": verification_passed,
            "verificationOutput": verification_output,
            "now": now,
        }),
    );

    let new_status = updated
        .get("status")
        .and_then(|v| v.as_str())
        .unwrap_or("active");
    if new_status == "completed" {
        return json!({
            "decision": "allow",
            "reason": format!(
                "Ralph loop '{}' completed at iteration {}.",
                updated.get("id").and_then(|v| v.as_str()).unwrap_or(""),
                updated.get("iteration").and_then(|v| v.as_i64()).unwrap_or(0)
            ),
            "updatedLoop": updated,
        });
    }
    if new_status == "capped" {
        return json!({
            "decision": "allow",
            "reason": format!(
                "Ralph loop '{}' reached maxIterations ({}).",
                updated.get("id").and_then(|v| v.as_str()).unwrap_or(""),
                updated.get("maxIterations").and_then(|v| v.as_i64()).unwrap_or(0)
            ),
            "updatedLoop": updated,
        });
    }

    let completion_promise = updated
        .get("completionPromise")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let promise_hint = if !completion_promise.is_empty() {
        format!("\nEmit <promise>{completion_promise}</promise> ONLY when all requirements are verified complete.")
    } else {
        String::new()
    };
    let verify_hint = if verification_passed == Some(false) && !verification_output.is_empty() {
        let tail: String = verification_output.chars().take(400).collect();
        format!("\nVerification command failed:\n{tail}")
    } else {
        String::new()
    };

    json!({
        "decision": "block",
        "reason": format!(
            "[Ralph Loop {}/{}] Continue working on task:\n{}{}{}",
            updated.get("iteration").and_then(|v| v.as_i64()).unwrap_or(0),
            updated.get("maxIterations").and_then(|v| v.as_i64()).unwrap_or(0),
            updated.get("prompt").and_then(|v| v.as_str()).unwrap_or(""),
            verify_hint,
            promise_hint
        ),
        "updatedLoop": updated,
    })
}

pub fn summarise_loops(loops: &[Value]) -> Value {
    let mut active = 0usize;
    let mut completed = 0usize;
    let mut capped = 0usize;
    let mut cancelled = 0usize;
    let mut total_iterations = 0i64;

    for lp in loops {
        total_iterations += lp.get("iteration").and_then(|v| v.as_i64()).unwrap_or(0);
        match lp.get("status").and_then(|v| v.as_str()).unwrap_or("") {
            "active" => active += 1,
            "completed" => completed += 1,
            "capped" => capped += 1,
            "cancelled" => cancelled += 1,
            _ => {}
        }
    }

    json!({
        "loops": loops,
        "counts": {
            "total": loops.len(),
            "active": active,
            "completed": completed,
            "capped": capped,
            "cancelled": cancelled,
            "totalIterations": total_iterations,
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn check_promise_matched_recognises_promise_tags_and_plain_substrings() {
        assert!(check_promise_matched(
            "All tests pass! <promise>DONE</promise>",
            "DONE"
        ));
        assert!(!check_promise_matched(
            "Still working <promise>NOT_YET</promise>",
            "DONE"
        ));
        assert!(check_promise_matched("Status: SHIP_IT_NOW", "SHIP_IT_NOW"));
        assert!(!check_promise_matched("anything", ""));
    }

    #[test]
    fn create_loop_state_validates_id_and_prompt_and_clamps_max_iterations() {
        let lp = create_loop_state(&json!({
            "id": "conv-1",
            "prompt": "Fix failing unit tests",
            "completionPromise": "ALL_GREEN",
            "maxIterations": 500,
            "now": 1000
        }))
        .unwrap();
        assert_eq!(lp["id"], json!("conv-1"));
        assert_eq!(lp["maxIterations"], json!(200));
        assert_eq!(lp["status"], json!("active"));
        assert_eq!(lp["iteration"], json!(0));

        assert!(create_loop_state(&json!({ "id": "", "prompt": "x" })).is_err());
        assert!(create_loop_state(&json!({ "id": "a", "prompt": "" })).is_err());
    }

    #[test]
    fn evaluate_stop_event_blocks_until_promise_is_matched_or_max_iterations_is_reached() {
        let mut lp = create_loop_state(&json!({
            "id": "conv-2",
            "prompt": "Implement feature X",
            "completionPromise": "FEATURE_X_READY",
            "maxIterations": 3,
            "now": 100
        }))
        .unwrap();

        let step1 = evaluate_stop_event(
            Some(&lp),
            &json!({
                "lastAssistantMessage": "Made progress on part 1.",
                "now": 200
            }),
        );
        assert_eq!(step1["decision"], json!("block"));
        assert!(step1["reason"]
            .as_str()
            .unwrap()
            .contains("[Ralph Loop 1/3]"));
        lp = step1["updatedLoop"].clone();
        assert_eq!(lp["iteration"], json!(1));
        assert_eq!(lp["status"], json!("active"));

        let step2 = evaluate_stop_event(
            Some(&lp),
            &json!({
                "lastAssistantMessage": "Done! <promise>FEATURE_X_READY</promise>",
                "now": 300
            }),
        );
        assert_eq!(step2["decision"], json!("allow"));
        assert_eq!(step2["updatedLoop"]["status"], json!("completed"));
        assert_eq!(step2["updatedLoop"]["iteration"], json!(2));
    }

    #[test]
    fn evaluate_stop_event_caps_loop_when_max_iterations_is_reached_without_promise() {
        let lp = create_loop_state(&json!({
            "id": "conv-3",
            "prompt": "Try once",
            "completionPromise": "DONE",
            "maxIterations": 1,
            "now": 100
        }))
        .unwrap();
        let res = evaluate_stop_event(
            Some(&lp),
            &json!({
                "lastAssistantMessage": "Still not done",
                "now": 200
            }),
        );
        assert_eq!(res["decision"], json!("allow"));
        assert_eq!(res["updatedLoop"]["status"], json!("capped"));
    }

    #[test]
    fn summarise_loops_counts_active_completed_and_capped_loops() {
        let s = summarise_loops(&[
            json!({ "id": "1", "status": "active", "iteration": 2 }),
            json!({ "id": "2", "status": "completed", "iteration": 4 }),
            json!({ "id": "3", "status": "capped", "iteration": 10 }),
        ]);
        assert_eq!(
            s["counts"],
            json!({
                "total": 3,
                "active": 1,
                "completed": 1,
                "capped": 1,
                "cancelled": 0,
                "totalIterations": 16
            })
        );
    }
}
