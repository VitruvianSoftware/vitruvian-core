// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

pub mod openui;

use serde_json::{json, Map, Value};
use std::collections::HashSet;

pub const PHASES: [&str; 5] = ["plan", "design", "delegate", "review", "close"];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TierInfo {
    pub id: &'static str,
    pub label: &'static str,
    pub model: &'static str,
    pub color: &'static str,
}

pub const TIERS: [(&str, TierInfo); 6] = [
    (
        "fable",
        TierInfo {
            id: "fable",
            label: "Fable",
            model: "Fable · high",
            color: "#7F77DD",
        },
    ),
    (
        "heavy",
        TierInfo {
            id: "heavy",
            label: "Heavy",
            model: "Opus · xhigh",
            color: "#D85A30",
        },
    ),
    (
        "careful",
        TierInfo {
            id: "careful",
            label: "Careful",
            model: "Opus · high",
            color: "#BA7517",
        },
    ),
    (
        "medium",
        TierInfo {
            id: "medium",
            label: "Medium",
            model: "Opus · medium",
            color: "#378ADD",
        },
    ),
    (
        "light",
        TierInfo {
            id: "light",
            label: "Light",
            model: "Opus · low",
            color: "#1D9E75",
        },
    ),
    (
        "other",
        TierInfo {
            id: "other",
            label: "Other",
            model: "inherit",
            color: "#888780",
        },
    ),
];

pub const SPECIALIST_DEFAULTS: [(&str, (&str, &str)); 10] = [
    ("beacon", ("heavy", "#E0A106")),
    ("wren", ("medium", "#A0703F")),
    ("atlas", ("heavy", "#378ADD")),
    ("ridge", ("careful", "#1D9E75")),
    ("forge", ("heavy", "#D85A30")),
    ("scout", ("light", "#3B9C5F")),
    ("aegis", ("careful", "#5B6CC9")),
    ("compass", ("fable", "#D0453F")),
    ("pace", ("light", "#12A5A0")),
    ("quill", ("light", "#8A63D2")),
];

pub fn blank_flow() -> Value {
    json!({
        "title": "savvy-flow",
        "total": 0,
        "done": 0,
        "running": 0,
        "phase": "plan",
        "isFinished": false,
        "tasks": [],
    })
}

pub fn normalize_text(text: &str) -> String {
    let lower = text.to_lowercase();
    let mut out = String::new();
    let mut in_sep = false;
    for ch in lower.chars() {
        if ch.is_alphanumeric() {
            if in_sep && !out.is_empty() {
                out.push(' ');
            }
            out.push(ch);
            in_sep = false;
        } else {
            in_sep = true;
        }
    }
    out.trim().to_string()
}

fn is_known_tier(s: &str) -> bool {
    TIERS.iter().any(|(k, _)| *k == s)
}

fn strip_colon_prefix(s: &str) -> &str {
    match s.find(':') {
        Some(idx) => &s[idx + 1..],
        None => s,
    }
}

pub fn infer_tier(type_name: &str, role_text: &str, explicit_tier: &str) -> String {
    let raw_explicit = strip_colon_prefix(explicit_tier)
        .trim_start_matches("savvy-")
        .trim()
        .to_ascii_lowercase();
    if !raw_explicit.is_empty() && is_known_tier(&raw_explicit) {
        return raw_explicit;
    }

    let lower_role = role_text.to_ascii_lowercase();
    for t in ["fable", "heavy", "careful", "medium", "light"] {
        let tag = format!("[{t}]");
        if lower_role.contains(&tag) {
            return t.to_string();
        }
    }

    let bare_type = strip_colon_prefix(type_name).trim().to_ascii_lowercase();
    let stripped = bare_type.trim_start_matches("savvy-");
    if bare_type.starts_with("savvy-") && is_known_tier(stripped) {
        return stripped.to_string();
    }
    for (spec, (tier, _)) in &SPECIALIST_DEFAULTS {
        if *spec == bare_type {
            return (*tier).to_string();
        }
    }
    "other".to_string()
}

fn is_new_flow(prev: Option<&Value>, input: &Value) -> bool {
    let Some(p) = prev.filter(|v| v.is_object()) else {
        return true;
    };
    if p.get("isFinished")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
    {
        return true;
    }
    if let Some(inp_title) = input.get("title").and_then(|v| v.as_str()) {
        let trimmed = inp_title.trim();
        let prev_title = p.get("title").and_then(|v| v.as_str()).unwrap_or("");
        if !trimmed.is_empty() && trimmed != prev_title {
            return true;
        }
    }
    false
}

fn clean_tasks(tasks: Option<&Value>) -> Option<Vec<Value>> {
    let arr = tasks?.as_array()?;
    let mut cleaned = Vec::new();
    for t in arr {
        let Some(obj) = t.as_object() else {
            continue;
        };
        let title = obj
            .get("title")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim()
            .to_string();
        if title.is_empty() {
            continue;
        }
        let spec_or_tier = obj
            .get("specialist")
            .and_then(|v| v.as_str())
            .or_else(|| obj.get("tier").and_then(|v| v.as_str()))
            .unwrap_or("");
        let exp_tier = obj.get("tier").and_then(|v| v.as_str()).unwrap_or("");
        let inferred = infer_tier(spec_or_tier, &title, exp_tier);
        let tier = if inferred == "other" {
            "medium".to_string()
        } else {
            inferred
        };
        let after: Vec<Value> = obj
            .get("after")
            .and_then(|v| v.as_array())
            .map(|a| {
                a.iter()
                    .filter_map(|n| n.as_i64().filter(|&x| x > 0).map(|x| json!(x)))
                    .collect()
            })
            .unwrap_or_default();
        let specialist = obj
            .get("specialist")
            .and_then(|v| v.as_str())
            .map(|s| s.trim())
            .filter(|s| !s.is_empty());

        let mut task_obj = Map::new();
        task_obj.insert("title".to_string(), json!(title));
        task_obj.insert("tier".to_string(), json!(tier));
        task_obj.insert("after".to_string(), Value::Array(after));
        if let Some(sp) = specialist {
            task_obj.insert("specialist".to_string(), json!(sp));
        }
        cleaned.push(Value::Object(task_obj));
    }
    Some(cleaned)
}

pub fn merge_flow_progress(prev: Option<&Value>, input: Option<&Value>) -> Value {
    let empty = json!({});
    let inp = input.filter(|v| v.is_object()).unwrap_or(&empty);
    let base = if is_new_flow(prev, inp) {
        blank_flow()
    } else {
        let mut b = blank_flow();
        if let (Some(b_obj), Some(p_obj)) = (b.as_object_mut(), prev.and_then(|v| v.as_object())) {
            for (k, v) in p_obj {
                b_obj.insert(k.clone(), v.clone());
            }
        }
        b
    };

    let tasks = clean_tasks(inp.get("tasks")).unwrap_or_else(|| {
        base.get("tasks")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default()
    });

    let raw_total = if let Some(t) = inp.get("total").and_then(|v| v.as_f64()) {
        t
    } else if inp.get("tasks").and_then(|v| v.as_array()).is_some() {
        tasks.len() as f64
    } else {
        base.get("total").and_then(|v| v.as_f64()).unwrap_or(0.0)
    };
    let total = if raw_total.is_finite() {
        (raw_total.round() as i64).max(0)
    } else {
        0
    };

    let raw_done = inp
        .get("done")
        .and_then(|v| v.as_f64())
        .unwrap_or_else(|| base.get("done").and_then(|v| v.as_f64()).unwrap_or(0.0));
    let done_unclamped = if raw_done.is_finite() {
        (raw_done.round() as i64).max(0)
    } else {
        0
    };
    let done = if total > 0 {
        done_unclamped.min(total)
    } else {
        done_unclamped
    };

    let raw_running = inp
        .get("running")
        .and_then(|v| v.as_f64())
        .unwrap_or_else(|| base.get("running").and_then(|v| v.as_f64()).unwrap_or(0.0));
    let running = if raw_running.is_finite() {
        (raw_running.round() as i64).max(0)
    } else {
        0
    };

    let phase = inp
        .get("phase")
        .and_then(|v| v.as_str())
        .filter(|p| PHASES.contains(p))
        .unwrap_or_else(|| base.get("phase").and_then(|v| v.as_str()).unwrap_or("plan"))
        .to_string();

    let is_finished = inp
        .get("finished")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let title = inp
        .get("title")
        .and_then(|v| v.as_str())
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| {
            base.get("title")
                .and_then(|v| v.as_str())
                .unwrap_or("savvy-flow")
        })
        .to_string();

    json!({
        "title": title,
        "total": total,
        "done": done,
        "running": if is_finished { 0 } else { running },
        "phase": if is_finished { "close" } else { phase.as_str() },
        "isFinished": is_finished,
        "tasks": tasks,
    })
}

fn price_row_for_model(model: &str) -> [f64; 4] {
    let lower = model.to_ascii_lowercase();
    if lower.contains("fable") || lower.contains("mythos") {
        [10.0, 50.0, 0.25, 12.5]
    } else if lower.contains("opus-5-5") {
        [4.0, 20.0, 0.2, 5.0]
    } else if lower.contains("opus") {
        [5.0, 25.0, 0.5, 6.25]
    } else if lower.contains("sonnet")
        || lower.contains("gemini-pro")
        || lower
            .split(|c: char| !c.is_ascii_alphanumeric())
            .any(|w| w == "pro")
    {
        [2.0, 10.0, 0.2, 2.5]
    } else if lower.contains("haiku") || lower.contains("flash") {
        [1.0, 5.0, 0.1, 1.25]
    } else {
        [4.0, 20.0, 0.2, 5.0]
    }
}

pub fn estimate_run_cost(model: &str, usage: &Value) -> Value {
    let model_str = if model.is_empty() { "inherit" } else { model };
    let empty = json!({});
    let u = usage.as_object().map(|_| usage).unwrap_or(&empty);
    let [in_rate, out_rate, read_rate, write_rate] = price_row_for_model(model_str);

    let has_explicit = u.get("input_tokens").is_some()
        || u.get("output_tokens").is_some()
        || u.get("inputTokens").is_some()
        || u.get("outputTokens").is_some();

    let num_field = |k1: &str, k2: &str| -> f64 {
        u.get(k1)
            .or_else(|| u.get(k2))
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0)
            .max(0.0)
    };

    let steps = num_field("steps", "steps");
    let tool_calls = num_field("toolCalls", "tool_calls");

    let input_tokens = if has_explicit {
        num_field("input_tokens", "inputTokens")
    } else {
        (steps * 420.0 + tool_calls * 180.0).max(0.0)
    };
    let output_tokens = if has_explicit {
        num_field("output_tokens", "outputTokens")
    } else {
        (steps * 160.0).max(0.0)
    };
    let cache_read_tokens = num_field("cache_read_input_tokens", "cacheReadTokens");
    let cache_write_tokens = num_field("cache_creation_input_tokens", "cacheWriteTokens");

    let tokens = input_tokens + output_tokens + cache_read_tokens + cache_write_tokens;
    let cost_usd = (input_tokens * in_rate
        + output_tokens * out_rate
        + cache_read_tokens * read_rate
        + cache_write_tokens * write_rate)
        / 1e6;
    let lower_model = model_str.to_ascii_lowercase();
    let context_max: i64 = if lower_model.contains("haiku") || lower_model.contains("flash_lite") {
        200_000
    } else {
        1_000_000
    };
    let formatted_tokens = if tokens >= 1e6 {
        format!("{:.1}M", tokens / 1e6)
    } else if tokens >= 1e3 {
        format!("{}k", (tokens / 1e3).round() as i64)
    } else {
        format!("{}", tokens.round() as i64)
    };
    let formatted_cost = if cost_usd < 10.0 {
        format!("${cost_usd:.2}")
    } else {
        format!("${cost_usd:.1}")
    };

    json!({
        "costUsd": cost_usd,
        "tokens": tokens as i64,
        "contextMax": context_max,
        "formattedCost": formatted_cost,
        "formattedTokens": formatted_tokens,
    })
}

fn read_tool_args(tc: &Value) -> Value {
    let Some(obj) = tc.as_object() else {
        return json!({});
    };
    let raw = obj
        .get("args")
        .or_else(|| obj.get("arguments"))
        .or_else(|| obj.get("input"))
        .or_else(|| obj.get("parameters"));
    match raw {
        Some(Value::String(s)) => serde_json::from_str(s).unwrap_or_else(|_| json!({})),
        Some(Value::Object(m)) => Value::Object(m.clone()),
        _ => json!({}),
    }
}

pub fn extract_subagents_from_transcript(jsonl_text: &str, inbox_notes: &[Value]) -> Value {
    let mut total_steps: i64 = 0;
    let mut tool_calls: i64 = 0;
    let mut tools_breakdown = Map::new();
    let mut subagent_ids: Vec<String> = Vec::new();
    let mut subagents_by_id: std::collections::HashMap<String, Value> =
        std::collections::HashMap::new();
    let mut round_counts_by_role: std::collections::HashMap<String, i64> =
        std::collections::HashMap::new();

    fn record_invoke(
        args: &Value,
        id_hint: Option<String>,
        status: &str,
        subagent_ids: &mut Vec<String>,
        subagents_by_id: &mut std::collections::HashMap<String, Value>,
        round_counts_by_role: &mut std::collections::HashMap<String, i64>,
    ) {
        let type_name = args
            .get("TypeName")
            .or_else(|| args.get("subagent_type"))
            .or_else(|| args.get("type"))
            .or_else(|| args.get("agent"))
            .and_then(|v| v.as_str())
            .unwrap_or("self")
            .trim()
            .to_string();
        let role = args
            .get("Role")
            .or_else(|| args.get("description"))
            .or_else(|| args.get("role"))
            .and_then(|v| v.as_str())
            .unwrap_or(&type_name)
            .trim()
            .to_string();
        let model = args
            .get("Model")
            .or_else(|| args.get("model"))
            .and_then(|v| v.as_str())
            .unwrap_or("inherit")
            .trim()
            .to_string();
        let workspace = args
            .get("Workspace")
            .or_else(|| args.get("workspace"))
            .and_then(|v| v.as_str())
            .unwrap_or("inherit")
            .to_string();
        let norm_role = normalize_text(if role.is_empty() { &type_name } else { &role });
        let round = round_counts_by_role.get(&norm_role).copied().unwrap_or(0) + 1;
        round_counts_by_role.insert(norm_role, round);

        let id = id_hint
            .or_else(|| {
                args.get("conversationId")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string())
            })
            .unwrap_or_else(|| format!("subagent-{}", subagents_by_id.len() + 1));

        let explicit_tier = args.get("tier").and_then(|v| v.as_str()).unwrap_or("");
        let tier = infer_tier(&type_name, &role, explicit_tier);
        let est = estimate_run_cost(&model, &json!({ "steps": 6, "toolCalls": 4 }));

        if !subagents_by_id.contains_key(&id) {
            subagent_ids.push(id.clone());
        }
        subagents_by_id.insert(
            id.clone(),
            json!({
                "id": id,
                "type": type_name,
                "role": role,
                "tier": tier,
                "model": model,
                "workspace": workspace,
                "round": round,
                "status": status,
                "messagesSent": 0,
                "tokens": est.get("tokens").cloned().unwrap_or(json!(0)),
                "costUsd": est.get("costUsd").cloned().unwrap_or(json!(0.0)),
                "formattedCost": est.get("formattedCost").cloned().unwrap_or(json!("$0.00")),
                "formattedTokens": est.get("formattedTokens").cloned().unwrap_or(json!("0")),
                "startedAt": 0,
            }),
        );
    }

    for line in jsonl_text.split('\n') {
        if line.trim().is_empty() {
            continue;
        }
        let Ok(entry) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        total_steps += 1;
        let tcs = entry
            .get("tool_calls")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();
        for tc in tcs {
            if !tc.is_object() {
                continue;
            }
            let name = tc
                .get("name")
                .or_else(|| tc.get("tool_name"))
                .and_then(|v| v.as_str())
                .unwrap_or("unknown")
                .to_string();
            tool_calls += 1;
            let prev_count = tools_breakdown
                .get(&name)
                .and_then(|v| v.as_i64())
                .unwrap_or(0);
            tools_breakdown.insert(name.clone(), json!(prev_count + 1));
            let args = read_tool_args(&tc);
            if name == "invoke_subagent" {
                let id_hint = tc
                    .get("id")
                    .or_else(|| tc.get("tool_call_id"))
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string())
                    .or_else(|| Some(format!("step-{total_steps}-{tool_calls}")));
                let status = if entry.get("status").and_then(|v| v.as_str()) == Some("ERROR") {
                    "failed"
                } else {
                    "done"
                };
                record_invoke(
                    &args,
                    id_hint,
                    status,
                    &mut subagent_ids,
                    &mut subagents_by_id,
                    &mut round_counts_by_role,
                );
            } else if name == "send_message" {
                let recipient = args
                    .get("Recipient")
                    .or_else(|| args.get("recipient"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .trim();
                if !recipient.is_empty() {
                    if let Some(existing) = subagents_by_id.get_mut(recipient) {
                        if let Some(obj) = existing.as_object_mut() {
                            let ms = obj
                                .get("messagesSent")
                                .and_then(|v| v.as_i64())
                                .unwrap_or(0);
                            let rd = obj.get("round").and_then(|v| v.as_i64()).unwrap_or(1);
                            obj.insert("messagesSent".to_string(), json!(ms + 1));
                            obj.insert("round".to_string(), json!(rd + 1));
                        }
                    }
                }
            }
        }
    }

    for raw_note in inbox_notes {
        let note: Value = match raw_note {
            Value::String(s) => match serde_json::from_str(s) {
                Ok(v) => v,
                Err(_) => continue,
            },
            other => other.clone(),
        };
        if !note.is_object() {
            continue;
        }
        let tool_name = note
            .get("tool_name")
            .or_else(|| note.get("toolName"))
            .or_else(|| note.get("name"))
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim();
        let args = if let Some(ti) = note.get("tool_input") {
            read_tool_args(&json!({ "args": ti }))
        } else {
            read_tool_args(&note)
        };
        if tool_name == "invoke_subagent"
            || args.get("TypeName").is_some()
            || args.get("Role").is_some()
        {
            let role_or_type = args
                .get("Role")
                .or_else(|| args.get("TypeName"))
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let norm_role = normalize_text(role_or_type);
            let already_tracked = !norm_role.is_empty()
                && subagents_by_id.values().any(|a| {
                    normalize_text(a.get("role").and_then(|v| v.as_str()).unwrap_or(""))
                        == norm_role
                });
            if !already_tracked {
                let id_hint = note
                    .get("id")
                    .or_else(|| note.get("tool_use_id"))
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string());
                let status = note
                    .get("status")
                    .and_then(|v| v.as_str())
                    .unwrap_or("running");
                record_invoke(
                    &args,
                    id_hint,
                    status,
                    &mut subagent_ids,
                    &mut subagents_by_id,
                    &mut round_counts_by_role,
                );
            }
        }
    }

    let ordered_subagents: Vec<Value> = subagent_ids
        .into_iter()
        .filter_map(|id| subagents_by_id.remove(&id))
        .collect();

    json!({
        "totalSteps": total_steps,
        "toolCalls": tool_calls,
        "toolsBreakdown": Value::Object(tools_breakdown),
        "subagents": ordered_subagents,
    })
}

pub fn summarise_fleet_state(options: &Value) -> Value {
    let empty = json!({});
    let opts = options.as_object().map(|_| options).unwrap_or(&empty);
    let flow = merge_flow_progress(None, opts.get("flow"));
    let parsed = match opts.get("transcript") {
        Some(t) if t.is_object() => t.clone(),
        Some(Value::String(s)) => {
            let notes = opts
                .get("inboxNotes")
                .and_then(|v| v.as_array())
                .cloned()
                .unwrap_or_default();
            extract_subagents_from_transcript(s, &notes)
        }
        _ => {
            let notes = opts
                .get("inboxNotes")
                .and_then(|v| v.as_array())
                .cloned()
                .unwrap_or_default();
            extract_subagents_from_transcript("", &notes)
        }
    };

    let subagents = parsed
        .get("subagents")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let started_norm: HashSet<String> = subagents
        .iter()
        .map(|a| {
            let r = a.get("role").and_then(|v| v.as_str()).unwrap_or("");
            let t = a.get("type").and_then(|v| v.as_str()).unwrap_or("");
            normalize_text(if r.is_empty() { t } else { r })
        })
        .collect();

    let is_finished = flow
        .get("isFinished")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let planned: Vec<Value> = if is_finished {
        Vec::new()
    } else {
        flow.get("tasks")
            .and_then(|v| v.as_array())
            .map(|tasks| {
                tasks
                    .iter()
                    .enumerate()
                    .filter_map(|(idx, t)| {
                        let title = t.get("title").and_then(|v| v.as_str()).unwrap_or("");
                        if started_norm.contains(&normalize_text(title)) {
                            return None;
                        }
                        let mut m = t.as_object()?.clone();
                        m.insert("number".to_string(), json!(idx + 1));
                        Some(Value::Object(m))
                    })
                    .collect()
            })
            .unwrap_or_default()
    };

    let running_count = subagents
        .iter()
        .filter(|a| a.get("status").and_then(|v| v.as_str()) == Some("running"))
        .count();
    let finished_count = subagents.len().saturating_sub(running_count);

    let total_steps = parsed
        .get("totalSteps")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let tool_calls = parsed
        .get("toolCalls")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let host_est = estimate_run_cost(
        "gemini-pro",
        &json!({ "steps": total_steps, "toolCalls": tool_calls }),
    );
    let fleet_cost_usd: f64 = subagents
        .iter()
        .map(|a| a.get("costUsd").and_then(|v| v.as_f64()).unwrap_or(0.0))
        .sum();
    let fleet_tokens: i64 = subagents
        .iter()
        .map(|a| a.get("tokens").and_then(|v| v.as_i64()).unwrap_or(0))
        .sum();
    let total_cost_usd = host_est
        .get("costUsd")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0)
        + fleet_cost_usd;
    let total_tokens = host_est.get("tokens").and_then(|v| v.as_i64()).unwrap_or(0) + fleet_tokens;
    let totals_est = estimate_run_cost(
        "opus-5-5",
        &json!({ "input_tokens": total_tokens, "output_tokens": 0 }),
    );

    let flow_total = flow.get("total").and_then(|v| v.as_i64()).unwrap_or(0);
    let flow_done = flow.get("done").and_then(|v| v.as_i64()).unwrap_or(0);
    let progress_pct: i64 = if is_finished {
        100
    } else if flow_total > 0 {
        (((flow_done as f64) / (flow_total as f64)) * 100.0)
            .round()
            .min(100.0) as i64
    } else if tool_calls > 0 {
        (((tool_calls as f64) / 45.0) * 100.0).round().min(100.0) as i64
    } else {
        0
    };

    let mut flow_out = flow.as_object().cloned().unwrap_or_default();
    let flow_running = if running_count > 0 {
        running_count as i64
    } else {
        flow.get("running").and_then(|v| v.as_i64()).unwrap_or(0)
    };
    flow_out.insert("running".to_string(), json!(flow_running));
    flow_out.insert("progressPct".to_string(), json!(progress_pct));

    let version = opts
        .get("version")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let conversation_id = opts
        .get("conversationId")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let connected = !conversation_id.is_empty() || total_steps > 0;
    let formatted_cost = if total_cost_usd < 10.0 {
        format!("${total_cost_usd:.2}")
    } else {
        format!("${total_cost_usd:.1}")
    };

    json!({
        "version": version,
        "conversationId": conversation_id,
        "connected": connected,
        "flow": Value::Object(flow_out),
        "totalSteps": total_steps,
        "toolCalls": tool_calls,
        "toolsBreakdown": parsed.get("toolsBreakdown").cloned().unwrap_or_else(|| json!({})),
        "subagents": subagents,
        "planned": planned,
        "counts": {
            "running": running_count,
            "finished": finished_count,
            "planned": planned.len(),
            "total": subagents.len() + planned.len(),
        },
        "totals": {
            "costUsd": total_cost_usd,
            "formattedCost": formatted_cost,
            "tokens": total_tokens,
            "formattedTokens": totals_est.get("formattedTokens").cloned().unwrap_or(json!("0")),
        },
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::openui::{
        compile_to_html, escape_html, openui_literal, parse_openui_lang, resolve_data_path,
        to_openui_lang, RenderOptions,
    };

    #[test]
    fn phases_and_tiers_expose_taxonomy() {
        assert_eq!(PHASES, ["plan", "design", "delegate", "review", "close"]);
        for tier in ["fable", "heavy", "careful", "medium", "light", "other"] {
            let found = TIERS.iter().find(|(k, _)| *k == tier);
            assert!(found.is_some(), "missing tier {tier}");
            let info = found.unwrap().1;
            assert!(info.color.starts_with('#') && info.color.len() == 7);
        }
    }

    #[test]
    fn infer_tier_resolves_brackets_prefixes_and_specialists() {
        assert_eq!(
            infer_tier("wren", "[careful] Audit RBAC policies", ""),
            "careful"
        );
        assert_eq!(infer_tier("savvy-heavy", "Refactor module", ""), "heavy");
        assert_eq!(infer_tier("beacon", "Coordinate wave 1", ""), "heavy");
        assert_eq!(infer_tier("aegis", "Review IAM bindings", ""), "careful");
        assert_eq!(infer_tier("scout", "Watch PR checks", ""), "light");
        assert_eq!(infer_tier("compass", "Clarify scope", ""), "fable");
        assert_eq!(infer_tier("custom-agent", "Do something", ""), "other");
    }

    #[test]
    fn merge_flow_progress_initializes_updates_and_resets() {
        let initial = merge_flow_progress(
            None,
            Some(&json!({
                "title": "Extensions Suite",
                "phase": "delegate",
                "tasks": [
                    { "title": "Build savvy-fleet", "tier": "savvy-heavy", "after": [] },
                    { "title": "Build ext-marketplace", "tier": "medium", "after": [1, -2, "x"] },
                    { "title": "   " }
                ]
            })),
        );
        assert_eq!(initial["title"], "Extensions Suite");
        assert_eq!(initial["phase"], "delegate");
        assert_eq!(initial["total"], 2);
        assert_eq!(initial["done"], 0);
        assert_eq!(
            initial["tasks"],
            json!([
                { "title": "Build savvy-fleet", "tier": "heavy", "after": [] },
                { "title": "Build ext-marketplace", "tier": "medium", "after": [1] }
            ])
        );

        let progressed = merge_flow_progress(
            Some(&initial),
            Some(&json!({ "done": 1, "phase": "review" })),
        );
        assert_eq!(progressed["done"], 1);
        assert_eq!(progressed["phase"], "review");
        assert_eq!(progressed["tasks"].as_array().unwrap().len(), 2);

        let finished = merge_flow_progress(
            Some(&progressed),
            Some(&json!({ "done": 5, "finished": true })),
        );
        assert_eq!(finished["done"], 2);
        assert_eq!(finished["phase"], "close");
        assert_eq!(finished["isFinished"], true);

        let restarted = merge_flow_progress(
            Some(&finished),
            Some(&json!({ "title": "Next Initiative" })),
        );
        assert_eq!(restarted["title"], "Next Initiative");
        assert_eq!(restarted["done"], 0);
        assert_eq!(restarted["total"], 0);
        assert_eq!(restarted["phase"], "plan");
        assert_eq!(restarted["isFinished"], false);
        assert_eq!(restarted["tasks"], json!([]));
    }

    #[test]
    fn estimate_run_cost_calculates_tokens_and_usd() {
        let opus = estimate_run_cost(
            "claude-opus-5-5",
            &json!({ "input_tokens": 500_000, "output_tokens": 50_000 }),
        );
        assert_eq!(opus["tokens"], 550_000);
        assert_eq!(opus["costUsd"], 3.0);
        assert_eq!(opus["formattedCost"], "$3.00");
        assert_eq!(opus["formattedTokens"], "550k");
        assert_eq!(opus["contextMax"], 1_000_000);

        let haiku = estimate_run_cost(
            "haiku-4",
            &json!({ "input_tokens": 100_000, "output_tokens": 20_000 }),
        );
        assert_eq!(haiku["contextMax"], 200_000);
        assert_eq!(haiku["costUsd"], 0.2);

        let step_est = estimate_run_cost("flash", &json!({ "steps": 10, "toolCalls": 5 }));
        assert!(step_est["tokens"].as_i64().unwrap() > 0);
        assert!(step_est["costUsd"].as_f64().unwrap() > 0.0);
    }

    #[test]
    fn extract_subagents_from_transcript_and_summarise() {
        let sample_jsonl = [
            json!({
                "step_index": 1,
                "status": "DONE",
                "tool_calls": [
                    {
                        "id": "sub-1",
                        "name": "invoke_subagent",
                        "args": {
                            "TypeName": "wren",
                            "Role": "[medium] Build savvy-fleet",
                            "Model": "inherit"
                        }
                    },
                    {
                        "id": "cmd-1",
                        "name": "run_command",
                        "args": { "CommandLine": "node --test" }
                    }
                ]
            })
            .to_string(),
            "not-valid-json".to_string(),
            json!({
                "step_index": 2,
                "status": "DONE",
                "tool_calls": [
                    {
                        "id": "msg-1",
                        "name": "send_message",
                        "args": { "Recipient": "sub-1", "Message": "Please add extra test" }
                    }
                ]
            })
            .to_string(),
        ]
        .join("\n");

        let inbox_notes = vec![Value::String(
            json!({
                "id": "sub-2",
                "tool_name": "invoke_subagent",
                "tool_input": {
                    "TypeName": "scout",
                    "Role": "Watch CI checks",
                    "Model": "flash"
                }
            })
            .to_string(),
        )];

        let extracted = extract_subagents_from_transcript(&sample_jsonl, &inbox_notes);
        assert_eq!(extracted["totalSteps"], 2);
        assert_eq!(extracted["toolCalls"], 3);
        assert_eq!(
            extracted["toolsBreakdown"],
            json!({
                "invoke_subagent": 1,
                "run_command": 1,
                "send_message": 1
            })
        );
        let subs = extracted["subagents"].as_array().unwrap();
        assert_eq!(subs.len(), 2);
        assert_eq!(subs[0]["type"], "wren");
        assert_eq!(subs[0]["tier"], "medium");
        assert_eq!(subs[0]["round"], 2);
        assert_eq!(subs[0]["messagesSent"], 1);
        assert_eq!(subs[1]["type"], "scout");
        assert_eq!(subs[1]["tier"], "light");
        assert_eq!(subs[1]["status"], "running");

        let state = summarise_fleet_state(&json!({
            "version": "0.1.0",
            "conversationId": "conv-12345678",
            "flow": {
                "title": "Fleet Rollout",
                "phase": "delegate",
                "done": 1,
                "tasks": [
                    { "title": "[medium] Build savvy-fleet", "tier": "medium" },
                    { "title": "Verify security posture", "tier": "careful", "specialist": "aegis" }
                ]
            },
            "transcript": json!({
                "step_index": 1,
                "status": "DONE",
                "tool_calls": [
                    {
                        "id": "sub-1",
                        "name": "invoke_subagent",
                        "args": {
                            "TypeName": "wren",
                            "Role": "[medium] Build savvy-fleet"
                        }
                    }
                ]
            }).to_string()
        }));
        assert_eq!(state["connected"], true);
        assert_eq!(state["flow"]["progressPct"], 50);
        assert_eq!(state["counts"]["finished"], 1);
        assert_eq!(state["counts"]["planned"], 1);
        assert_eq!(state["planned"][0]["title"], "Verify security posture");
        assert_eq!(state["planned"][0]["specialist"], "aegis");
    }

    #[test]
    fn openui_lang_renders_and_summarises_fleet_state() {
        let parsed = parse_openui_lang(
            "
            # comment
            root = Card([title, Kpi(\"Subagents\", 2, \"1 running\", \"info\", 50)])
            title = Header(\"Savvy Fleet\", \"v0.1.0\", \"1 running\", \"info\")
            ",
            &json!({}),
        );
        assert_eq!(parsed.order, vec!["root".to_string(), "title".to_string()]);
        assert_eq!(parsed.root["$component"], "Card");

        let ctx = json!({
            "data": {
                "rows": [
                    { "agent": "wren", "tier": "medium" },
                    { "agent": "scout", "tier": "light" }
                ]
            }
        });
        assert_eq!(
            resolve_data_path(&ctx, "data.rows.agent"),
            Some(json!(["wren", "scout"]))
        );

        let html = compile_to_html(
            &to_openui_lang(Some(&json!({
                "version": "0.1.0",
                "subagents": [
                    {
                        "type": "wren",
                        "tier": "medium",
                        "role": "<script>alert(1)</script>",
                        "status": "running"
                    }
                ]
            }))),
            &json!({}),
            &RenderOptions {
                title: "Savvy Fleet".to_string(),
                footer: "fleet-footer".to_string(),
                ..RenderOptions::default()
            },
        );
        assert!(html.starts_with("<!DOCTYPE html>"));
        assert!(!html.contains("<script>alert(1)"));
        assert!(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"));
        assert_eq!(escape_html(&Value::Null), "");
        assert_eq!(openui_literal(&json!("a\nb")), "\"a\\nb\"");

        let empty_dsl = to_openui_lang(None);
        let empty_parsed = parse_openui_lang(&empty_dsl, &json!({}));
        assert_eq!(
            empty_parsed.root["args"][0][0],
            json!({
                "$component": "Header",
                "args": ["Savvy Fleet", "", "idle", "neutral"]
            })
        );

        let dsl = to_openui_lang(Some(&json!({
            "version": "0.1.0",
            "flow": { "title": "Extensions Suite", "phase": "delegate", "isFinished": false },
            "totalSteps": 14,
            "toolCalls": 9,
            "totals": { "formattedCost": "$0.42", "formattedTokens": "18k" },
            "subagents": [
                { "type": "wren", "tier": "medium", "role": "Build savvy-fleet", "status": "running" },
                { "type": "scout", "tier": "light", "role": "Run unit tests", "status": "done" }
            ],
            "planned": [
                { "specialist": "aegis", "tier": "careful", "title": "Security review" }
            ]
        })));
        assert!(dsl.starts_with("# savvy-fleet state as OpenUI Lang v0.5\nroot = Card(["));
        let p = parse_openui_lang(&dsl, &json!({}));
        assert_eq!(
            p.root["args"][0][0]["args"],
            json!(["Savvy Fleet", "v0.1.0", "1 running", "info"])
        );
    }
}
