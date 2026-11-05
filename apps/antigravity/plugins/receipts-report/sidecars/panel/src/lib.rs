// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

pub mod openui;

use openui::escape_html;
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, BTreeSet};

pub fn project_from_path(workspace_path: &str) -> String {
    let trimmed = workspace_path.trim().trim_end_matches('/');
    if trimmed.is_empty() {
        return "unassigned".to_string();
    }
    let parts: Vec<&str> = trimmed.split('/').filter(|s| !s.is_empty()).collect();
    parts.last().copied().unwrap_or("unassigned").to_string()
}

pub fn parse_transcript_jsonl(jsonl_text: &str, meta: &Value) -> Value {
    let session_id = meta
        .get("sessionId")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .unwrap_or("unknown");
    let workspace_path = meta
        .get("workspacePath")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    let mut user_turns = 0i64;
    let mut assistant_turns = 0i64;
    let mut tool_calls = 0i64;
    let mut tool_counts: BTreeMap<String, i64> = BTreeMap::new();
    let mut files_touched: BTreeSet<String> = BTreeSet::new();
    let mut total_chars = 0usize;
    let mut detected_workspace = workspace_path.to_string();

    for raw_line in jsonl_text.lines() {
        let trimmed = raw_line.trim();
        if trimmed.is_empty() {
            continue;
        }
        total_chars += trimmed.len();
        let Ok(entry) = serde_json::from_str::<Value>(trimmed) else {
            continue;
        };
        let Some(obj) = entry.as_object() else {
            continue;
        };

        if detected_workspace.is_empty() {
            if let Some(wp) = obj.get("workspacePath").and_then(|v| v.as_str()) {
                if !wp.is_empty() {
                    detected_workspace = wp.to_string();
                }
            } else if let Some(wp) = obj
                .get("workspacePaths")
                .and_then(|v| v.as_array())
                .and_then(|a| a.first())
                .and_then(|v| v.as_str())
            {
                if !wp.is_empty() {
                    detected_workspace = wp.to_string();
                }
            }
        }

        let role_raw = obj
            .get("role")
            .or_else(|| obj.get("type"))
            .or_else(|| obj.get("sender"))
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_ascii_lowercase();

        if role_raw == "user" || role_raw == "human" {
            user_turns += 1;
        } else if role_raw == "assistant" || role_raw == "model" {
            assistant_turns += 1;
        }

        let mut calls: Vec<Value> = Vec::new();
        if let Some(arr) = obj.get("toolCalls").and_then(|v| v.as_array()) {
            calls.extend(arr.iter().cloned());
        } else if let Some(tc) = obj.get("toolCall").filter(|v| v.is_object()) {
            calls.push(tc.clone());
        } else if role_raw == "tool_use" || role_raw == "toolcall" {
            calls.push(entry.clone());
        }

        for tc in calls {
            let Some(tc_obj) = tc.as_object() else {
                continue;
            };
            let name = tc_obj
                .get("name")
                .or_else(|| tc_obj.get("toolName"))
                .or_else(|| tc_obj.get("tool"))
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
                .unwrap_or("unknown");
            tool_calls += 1;
            *tool_counts.entry(name.to_string()).or_insert(0) += 1;

            let args = tc_obj
                .get("args")
                .or_else(|| tc_obj.get("input"))
                .and_then(|v| v.as_object());
            let fp = args
                .and_then(|a| {
                    a.get("Path")
                        .or_else(|| a.get("AbsolutePath"))
                        .or_else(|| a.get("file_path"))
                        .or_else(|| a.get("path"))
                })
                .or_else(|| tc_obj.get("filePath"))
                .and_then(|v| v.as_str())
                .unwrap_or("");
            if !fp.is_empty() {
                files_touched.insert(fp.to_string());
            }
        }
    }

    let estimated_tokens = ((total_chars as f64) / 4.0).round() as i64;
    let project = project_from_path(&detected_workspace);
    let mut tc_map = Map::new();
    for (k, v) in tool_counts {
        tc_map.insert(k, json!(v));
    }
    let files_vec: Vec<Value> = files_touched.into_iter().map(Value::String).collect();

    json!({
        "sessionId": session_id,
        "project": project,
        "workspacePath": detected_workspace,
        "userTurns": user_turns,
        "assistantTurns": assistant_turns,
        "totalTurns": user_turns + assistant_turns,
        "toolCalls": tool_calls,
        "toolCounts": Value::Object(tc_map),
        "filesTouched": files_vec,
        "estimatedTokens": estimated_tokens,
    })
}

pub fn aggregate_project_receipts(sessions: &[Value]) -> Value {
    struct ProjAcc {
        project: String,
        session_count: i64,
        user_turns: i64,
        assistant_turns: i64,
        total_turns: i64,
        total_tool_calls: i64,
        estimated_tokens: i64,
        tool_counts: BTreeMap<String, i64>,
        files_set: BTreeSet<String>,
    }

    let mut by_project: BTreeMap<String, ProjAcc> = BTreeMap::new();
    let mut proj_order: Vec<String> = Vec::new();
    let mut totals_sessions = 0i64;
    let mut totals_user = 0i64;
    let mut totals_assistant = 0i64;
    let mut totals_turns = 0i64;
    let mut totals_tools = 0i64;
    let mut totals_tokens = 0i64;
    let mut global_tools: BTreeMap<String, i64> = BTreeMap::new();
    let mut global_files: BTreeSet<String> = BTreeSet::new();

    for s in sessions {
        let Some(obj) = s.as_object() else {
            continue;
        };
        let proj = obj
            .get("project")
            .and_then(|v| v.as_str())
            .filter(|p| !p.is_empty())
            .unwrap_or("unassigned")
            .to_string();
        if !by_project.contains_key(&proj) {
            proj_order.push(proj.clone());
            by_project.insert(
                proj.clone(),
                ProjAcc {
                    project: proj.clone(),
                    session_count: 0,
                    user_turns: 0,
                    assistant_turns: 0,
                    total_turns: 0,
                    total_tool_calls: 0,
                    estimated_tokens: 0,
                    tool_counts: BTreeMap::new(),
                    files_set: BTreeSet::new(),
                },
            );
        }
        let p = by_project.get_mut(&proj).unwrap();
        let u = obj.get("userTurns").and_then(|v| v.as_i64()).unwrap_or(0);
        let a = obj
            .get("assistantTurns")
            .and_then(|v| v.as_i64())
            .unwrap_or(0);
        let t = obj.get("totalTurns").and_then(|v| v.as_i64()).unwrap_or(0);
        let tc = obj.get("toolCalls").and_then(|v| v.as_i64()).unwrap_or(0);
        let tok = obj
            .get("estimatedTokens")
            .and_then(|v| v.as_i64())
            .unwrap_or(0);

        p.session_count += 1;
        p.user_turns += u;
        p.assistant_turns += a;
        p.total_turns += t;
        p.total_tool_calls += tc;
        p.estimated_tokens += tok;

        totals_sessions += 1;
        totals_user += u;
        totals_assistant += a;
        totals_turns += t;
        totals_tools += tc;
        totals_tokens += tok;

        if let Some(t_counts) = obj.get("toolCounts").and_then(|v| v.as_object()) {
            for (tool, count_val) in t_counts {
                let c = count_val.as_i64().unwrap_or(0);
                *p.tool_counts.entry(tool.clone()).or_insert(0) += c;
                *global_tools.entry(tool.clone()).or_insert(0) += c;
            }
        }
        if let Some(files) = obj.get("filesTouched").and_then(|v| v.as_array()) {
            for f in files.iter().filter_map(|v| v.as_str()) {
                p.files_set.insert(f.to_string());
                global_files.insert(f.to_string());
            }
        }
    }

    let mut projects_vec: Vec<Value> = proj_order
        .into_iter()
        .filter_map(|name| by_project.remove(&name))
        .map(|p| {
            let mut tc_obj = Map::new();
            for (k, v) in p.tool_counts {
                tc_obj.insert(k, json!(v));
            }
            let files_count = p.files_set.len();
            let files_arr: Vec<Value> = p.files_set.into_iter().map(Value::String).collect();
            json!({
                "project": p.project,
                "sessionCount": p.session_count,
                "userTurns": p.user_turns,
                "assistantTurns": p.assistant_turns,
                "totalTurns": p.total_turns,
                "totalToolCalls": p.total_tool_calls,
                "estimatedTokens": p.estimated_tokens,
                "toolCounts": Value::Object(tc_obj),
                "filesTouched": files_arr,
                "filesTouchedCount": files_count,
            })
        })
        .collect();

    projects_vec.sort_by(|a, b| {
        let tb = b
            .get("estimatedTokens")
            .and_then(|v| v.as_i64())
            .unwrap_or(0);
        let ta = a
            .get("estimatedTokens")
            .and_then(|v| v.as_i64())
            .unwrap_or(0);
        tb.cmp(&ta)
    });

    let mut global_tc_obj = Map::new();
    for (k, v) in global_tools {
        global_tc_obj.insert(k, json!(v));
    }

    json!({
        "projects": projects_vec,
        "totals": {
            "sessionCount": totals_sessions,
            "userTurns": totals_user,
            "assistantTurns": totals_assistant,
            "totalTurns": totals_turns,
            "totalToolCalls": totals_tools,
            "estimatedTokens": totals_tokens,
            "toolCounts": Value::Object(global_tc_obj),
            "filesTouchedCount": global_files.len(),
        },
        "sessions": sessions,
    })
}

pub fn detect_token_hotspots(aggregate: &Value, threshold_ratio: f64) -> Vec<Value> {
    let totals = aggregate
        .get("totals")
        .cloned()
        .unwrap_or_else(|| json!({}));
    let total_calls = totals
        .get("totalToolCalls")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    if total_calls <= 0 {
        return Vec::new();
    }

    let mut hotspots = Vec::new();
    if let Some(tc_map) = totals.get("toolCounts").and_then(|v| v.as_object()) {
        for (tool, count_val) in tc_map {
            let count = count_val.as_i64().unwrap_or(0);
            let share = (count as f64) / (total_calls as f64);
            if share >= threshold_ratio {
                let pct = (share * 1000.0).round() / 10.0;
                hotspots.push(json!({
                    "tool": tool,
                    "count": count,
                    "sharePercent": pct,
                    "recommendation": format!(
                        "Tool '{}' accounts for {}% of all tool invocations; consider batching or caching repeated calls.",
                        tool,
                        (share * 100.0).round() as i64
                    ),
                }));
            }
        }
    }
    hotspots.sort_by(|a, b| {
        let cb = b.get("count").and_then(|v| v.as_i64()).unwrap_or(0);
        let ca = a.get("count").and_then(|v| v.as_i64()).unwrap_or(0);
        cb.cmp(&ca)
    });
    hotspots
}

fn csv_cell(v: &str) -> String {
    if v.contains(',') || v.contains('"') || v.contains('\n') {
        format!("\"{}\"", v.replace('"', "\"\""))
    } else {
        v.to_string()
    }
}

pub fn format_csv_receipt(aggregate: &Value) -> String {
    let header = "project,sessions,user_turns,assistant_turns,total_turns,tool_calls,estimated_tokens,files_touched";
    let projects = aggregate
        .get("projects")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let mut rows = Vec::with_capacity(projects.len() + 1);
    rows.push(header.to_string());
    for p in projects {
        let cells = [
            csv_cell(p.get("project").and_then(|v| v.as_str()).unwrap_or("")),
            p.get("sessionCount")
                .and_then(|v| v.as_i64())
                .unwrap_or(0)
                .to_string(),
            p.get("userTurns")
                .and_then(|v| v.as_i64())
                .unwrap_or(0)
                .to_string(),
            p.get("assistantTurns")
                .and_then(|v| v.as_i64())
                .unwrap_or(0)
                .to_string(),
            p.get("totalTurns")
                .and_then(|v| v.as_i64())
                .unwrap_or(0)
                .to_string(),
            p.get("totalToolCalls")
                .and_then(|v| v.as_i64())
                .unwrap_or(0)
                .to_string(),
            p.get("estimatedTokens")
                .and_then(|v| v.as_i64())
                .unwrap_or(0)
                .to_string(),
            p.get("filesTouchedCount")
                .and_then(|v| v.as_i64())
                .unwrap_or(0)
                .to_string(),
        ];
        rows.push(cells.join(","));
    }
    format!("{}\n", rows.join("\n"))
}

pub fn render_html_receipt(aggregate: &Value) -> String {
    let projects = aggregate
        .get("projects")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let totals = aggregate
        .get("totals")
        .cloned()
        .unwrap_or_else(|| json!({}));

    let rows = projects
        .iter()
        .map(|p| {
            format!(
                "<tr><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td></tr>",
                escape_html(p.get("project").and_then(|v| v.as_str()).unwrap_or("")),
                p.get("sessionCount").and_then(|v| v.as_i64()).unwrap_or(0),
                p.get("totalTurns").and_then(|v| v.as_i64()).unwrap_or(0),
                p.get("totalToolCalls")
                    .and_then(|v| v.as_i64())
                    .unwrap_or(0),
                p.get("estimatedTokens")
                    .and_then(|v| v.as_i64())
                    .unwrap_or(0),
                p.get("filesTouchedCount")
                    .and_then(|v| v.as_i64())
                    .unwrap_or(0)
            )
        })
        .collect::<Vec<_>>()
        .join("");

    let session_count = totals
        .get("sessionCount")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let total_turns = totals
        .get("totalTurns")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let total_tools = totals
        .get("totalToolCalls")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let est_tokens = totals
        .get("estimatedTokens")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);

    format!(
        "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\" />\n<title>Antigravity Receipts Report</title>\n</head>\n<body>\n  <h1>Antigravity Receipts Report</h1>\n  <p>Sessions: {session_count} · Turns: {total_turns} · Tool Calls: {total_tools} · Estimated Tokens: {est_tokens}</p>\n  <table>\n    <thead><tr><th>Project</th><th>Sessions</th><th>Turns</th><th>Tool Calls</th><th>Est. Tokens</th><th>Files Touched</th></tr></thead>\n    <tbody>{rows}</tbody>\n  </table>\n</body>\n</html>"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_transcript_jsonl_extracts_turns_tool_calls_and_files_touched() {
        let jsonl = [
            serde_json::to_string(&json!({
                "role": "user",
                "content": "Fix the bug",
                "workspacePath": "/work/vitruvian-core"
            }))
            .unwrap(),
            serde_json::to_string(&json!({
                "role": "assistant",
                "content": "Reading file",
                "toolCalls": [
                    { "name": "view_file", "args": { "AbsolutePath": "/work/vitruvian-core/src/a.ts" } },
                    { "name": "edit_file", "args": { "Path": "/work/vitruvian-core/src/a.ts" } }
                ]
            }))
            .unwrap(),
        ]
        .join("\n");

        let parsed = parse_transcript_jsonl(&jsonl, &json!({ "sessionId": "s1" }));
        assert_eq!(parsed["sessionId"], json!("s1"));
        assert_eq!(parsed["project"], json!("vitruvian-core"));
        assert_eq!(parsed["userTurns"], json!(1));
        assert_eq!(parsed["assistantTurns"], json!(1));
        assert_eq!(parsed["toolCalls"], json!(2));
        assert_eq!(
            parsed["toolCounts"],
            json!({ "view_file": 1, "edit_file": 1 })
        );
        assert_eq!(
            parsed["filesTouched"],
            json!(["/work/vitruvian-core/src/a.ts"])
        );
        assert!(parsed["estimatedTokens"].as_i64().unwrap() > 0);
    }

    #[test]
    fn aggregate_project_receipts_and_exporters_produce_csv_and_html_receipts() {
        let s1 = parse_transcript_jsonl(
            &serde_json::to_string(&json!({
                "role": "assistant",
                "workspacePath": "/w/repo-a",
                "toolCalls": [
                    { "name": "run_command", "args": {} },
                    { "name": "run_command", "args": {} },
                    { "name": "view_file", "args": { "Path": "x.js" } }
                ]
            }))
            .unwrap(),
            &json!({ "sessionId": "s1" }),
        );
        let agg = aggregate_project_receipts(&[s1]);
        assert_eq!(agg["totals"]["sessionCount"], json!(1));
        assert_eq!(agg["totals"]["totalToolCalls"], json!(3));
        assert_eq!(agg["projects"][0]["project"], json!("repo-a"));

        let hotspots = detect_token_hotspots(&agg, 0.5);
        assert_eq!(hotspots.len(), 1);
        assert_eq!(hotspots[0]["tool"], json!("run_command"));

        let csv = format_csv_receipt(&agg);
        assert!(csv.contains("project,sessions,user_turns"));
        assert!(csv.contains("repo-a,1,0,1,1,3"));

        let html = render_html_receipt(&agg);
        assert!(html.contains("<!DOCTYPE html>"));
        assert!(html.contains("repo-a"));
    }

    #[test]
    fn project_from_path_falls_back_gracefully() {
        assert_eq!(project_from_path("/a/b/my-app/"), "my-app");
        assert_eq!(project_from_path(""), "unassigned");
    }
}
