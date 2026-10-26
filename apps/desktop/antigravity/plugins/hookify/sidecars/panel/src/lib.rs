// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

pub mod openui;

pub use evaluate_rules::{
    evaluate_condition, evaluate_pre_tool_use, evaluate_rule, evaluate_stop,
    extract_field_from_payload, handle_hookify_payload, parse_hookify_markdown, resolve_app_dir,
    serialize_hookify_markdown, PreToolEvalSummary, RuleEvalResult, StopEvalSummary,
    SUPPORTED_ACTIONS, SUPPORTED_OPERATORS,
};

use serde_json::{json, Value};

pub fn summarise_hookify_state(rules: &[Value], audit_log: &[Value]) -> Value {
    let total_rules = rules.len();
    let enabled_rules = rules
        .iter()
        .filter(|r| r.get("enabled").and_then(|v| v.as_bool()) != Some(false))
        .count();
    let block_rules = rules
        .iter()
        .filter(|r| {
            r.get("enabled").and_then(|v| v.as_bool()) != Some(false)
                && matches!(
                    r.get("action").and_then(|v| v.as_str()).unwrap_or(""),
                    "block" | "deny"
                )
        })
        .count();
    let warn_rules = rules
        .iter()
        .filter(|r| {
            r.get("enabled").and_then(|v| v.as_bool()) != Some(false)
                && matches!(
                    r.get("action").and_then(|v| v.as_str()).unwrap_or("warn"),
                    "warn" | "ask" | "force_ask"
                )
        })
        .count();
    let overwrite_rules = rules
        .iter()
        .filter(|r| {
            r.get("enabled").and_then(|v| v.as_bool()) != Some(false)
                && r.get("action").and_then(|v| v.as_str()) == Some("overwrite")
        })
        .count();

    let mut blocked = 0usize;
    let mut warned = 0usize;
    let mut overwritten = 0usize;
    for ev in audit_log {
        match ev.get("decision").and_then(|v| v.as_str()).unwrap_or("") {
            "deny" | "block" => blocked += 1,
            "ask" | "force_ask" | "warn" => warned += 1,
            "overwrite" => overwritten += 1,
            _ => {}
        }
    }

    let recent_audit: Vec<Value> = audit_log.iter().take(50).cloned().collect();

    json!({
        "rules": rules,
        "auditLog": recent_audit,
        "summary": {
            "totalRules": total_rules,
            "enabledRules": enabled_rules,
            "blockRules": block_rules,
            "warnRules": warn_rules,
            "overwriteRules": overwrite_rules,
            "eventStats": {
                "total": audit_log.len(),
                "blocked": blocked,
                "warned": warned,
                "overwritten": overwritten,
            }
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_hookify_markdown_parses_simple_and_multi_condition_rules() {
        let simple_md = "---\nname: block-rm\nenabled: true\nevent: bash\npattern: rm\\s+-rf\naction: block\n---\n\nDangerous rm command detected!";
        let parsed =
            parse_hookify_markdown(simple_md, "/w/.gemini/hookify.block-rm.local.md").unwrap();
        assert_eq!(parsed["name"], json!("block-rm"));
        assert_eq!(parsed["enabled"], json!(true));
        assert_eq!(parsed["event"], json!("bash"));
        assert_eq!(parsed["action"], json!("block"));
        assert_eq!(parsed["message"], json!("Dangerous rm command detected!"));

        let multi_md = "---\nname: block-env-edits\nenabled: true\nevent: file\naction: block\nconditions:\n  - field: file_path\n    operator: regex_match\n    pattern: \\.env$\n  - field: new_text\n    operator: contains\n    pattern: API_KEY\n---\n\nDo not hardcode API keys in .env files.";
        let multi = parse_hookify_markdown(multi_md, "").unwrap();
        let conds = multi["conditions"].as_array().unwrap();
        assert_eq!(conds.len(), 2);
        assert_eq!(conds[0]["field"], json!("file_path"));
        assert_eq!(conds[1]["operator"], json!("contains"));
    }

    #[test]
    fn serialize_hookify_markdown_round_trips_rule_objects() {
        let rule = json!({
            "name": "warn-todo",
            "enabled": true,
            "event": "file",
            "action": "warn",
            "pattern": "TODO|FIXME",
            "message": "Remember to file an issue for TODOs."
        });
        let md = serialize_hookify_markdown(&rule);
        let round_trip = parse_hookify_markdown(&md, "").unwrap();
        assert_eq!(round_trip["name"], json!("warn-todo"));
        assert_eq!(round_trip["action"], json!("warn"));
        assert_eq!(
            round_trip["message"],
            json!("Remember to file an issue for TODOs.")
        );
    }

    #[test]
    fn evaluate_pre_tool_use_blocks_matching_bash_and_file_commands() {
        let rules = vec![
            parse_hookify_markdown(
                "---\nname: no-force-push\nenabled: true\nevent: bash\npattern: git\\s+push\\s+--force\naction: block\n---\nUse --force-with-lease instead.",
                "",
            )
            .unwrap(),
            parse_hookify_markdown(
                "---\nname: warn-console-log\nenabled: true\nevent: file\npattern: console\\.log\\(\naction: warn\n---\nAvoid console.log in production code.",
                "",
            )
            .unwrap(),
        ];

        let blocked = evaluate_pre_tool_use(
            &rules,
            &json!({
                "toolCall": {
                    "name": "run_command",
                    "args": { "CommandLine": "git push --force origin main" }
                }
            }),
        );
        assert_eq!(blocked.decision, "deny");
        assert!(blocked.reason.contains("--force-with-lease"));

        let warned = evaluate_pre_tool_use(
            &rules,
            &json!({
                "toolCall": {
                    "name": "write_file",
                    "args": { "Path": "src/app.js", "Content": "console.log('hi')" }
                }
            }),
        );
        assert_eq!(warned.decision, "ask");
        assert_eq!(warned.matched_rules.len(), 1);
    }

    #[test]
    fn evaluate_stop_blocks_stop_when_stop_rule_matches() {
        let rules = vec![parse_hookify_markdown(
            "---\nname: check-uncommitted\nenabled: true\nevent: stop\nfield: reason\npattern: UNCOMMITTED_WORK\naction: block\n---\nCommit your work before stopping.",
            "",
        )
        .unwrap()];

        let res = evaluate_stop(
            &rules,
            &json!({ "reason": "Leaving UNCOMMITTED_WORK for later" }),
        );
        assert!(!res.continue_flag);
        assert!(res.stop_reason.contains("Commit your work"));
    }

    #[test]
    fn summarise_hookify_state_computes_counts_accurately() {
        let s = summarise_hookify_state(
            &[
                json!({ "name": "r1", "enabled": true, "event": "bash", "action": "block" }),
                json!({ "name": "r2", "enabled": false, "event": "file", "action": "warn" }),
            ],
            &[
                json!({ "decision": "block" }),
                json!({ "decision": "warn" }),
            ],
        );
        assert_eq!(s["summary"]["totalRules"], json!(2));
        assert_eq!(s["summary"]["enabledRules"], json!(1));
        assert_eq!(s["summary"]["blockRules"], json!(1));
        assert_eq!(s["summary"]["eventStats"]["blocked"], json!(1));
        assert_eq!(s["summary"]["eventStats"]["warned"], json!(1));
    }
}
