// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use std::env;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

pub const DEFAULT_RESPONSE_CONTRACT: &str = "RESPONSE CONTRACT: Scale to the question.\n\
- Simple or factual question: one or two sentences. No headers, no sections.\n\
- Substantive work: GIST first (one or two plain sentences, answer first, no jargon), then DETAIL (how it works, evidence, caveats).\n\
- SURPRISE first: if a finding contradicts what the user expects, or they may have missed it, it goes at the very top.\n\
- CONFIDENCE: mark what you verified versus what you assumed. Never present a guess as a fact.\n\
- CHOICES: give your pick and a one-line why. Alternatives only if they would change the decision.\n\
- DIAGRAM only when it earns its place: a workflow, pipeline, state machine or genuinely complex topic.\n\
- NEXT only when the user must do or decide something, or there is a concrete follow-up. Otherwise end after the detail. Never write 'Nothing needed from you.'";

const FILLER_PHRASES: &[&str] = &[
    "nothing needed from you",
    "nothing for you",
    "no action needed",
    "no action required",
    "no action is needed",
    "no action is required",
    "nothing needed",
    "nothing is needed",
    "nothing else needed",
    "nothing else is needed",
];

/// Resolves the live-context state directory from `STATE_DIR`, `ANTIGRAVITY_APP_DATA_DIR`, or `HOME`.
pub fn resolve_state_dir() -> Option<PathBuf> {
    if let Ok(dir) = env::var("STATE_DIR") {
        if !dir.is_empty() {
            return Some(PathBuf::from(dir));
        }
    }
    if let Ok(app_data) = env::var("ANTIGRAVITY_APP_DATA_DIR") {
        if !app_data.is_empty() {
            return Some(Path::new(&app_data).join("live-context-state"));
        }
    }
    if let Ok(home) = env::var("HOME") {
        if !home.is_empty() {
            return Some(
                Path::new(&home)
                    .join(".gemini")
                    .join("antigravity")
                    .join("live-context-state"),
            );
        }
    }
    None
}

fn val_as_str<'a>(obj: &'a Map<String, Value>, key: &str) -> Option<&'a str> {
    obj.get(key).and_then(|v| v.as_str())
}

fn val_to_string(v: Option<&Value>) -> String {
    match v {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Number(n)) => n.to_string(),
        Some(Value::Bool(b)) => b.to_string(),
        _ => String::new(),
    }
}

fn val_as_f64(v: Option<&Value>, default: f64) -> f64 {
    match v {
        Some(Value::Number(n)) => n.as_f64().unwrap_or(default),
        Some(Value::String(s)) => s.trim().parse::<f64>().unwrap_or(default),
        _ => default,
    }
}

/// Formats live local Git state and GitHub open/merged pull requests into a concise context block.
pub fn format_live_git_summary(
    git: Option<&Map<String, Value>>,
    github: Option<&Map<String, Value>>,
    include_git: bool,
    include_github: bool,
) -> String {
    let mut sections = Vec::new();

    if include_git {
        if let Some(g) = git {
            let branch_raw = val_as_str(g, "branch").unwrap_or("");
            let head_sha = val_as_str(g, "headSha").unwrap_or("");
            if !branch_raw.is_empty() || !head_sha.is_empty() {
                let branch = if branch_raw.is_empty() {
                    "detached"
                } else {
                    branch_raw
                };
                let sha = if head_sha.is_empty() {
                    String::new()
                } else {
                    format!(" ({head_sha})")
                };
                let dirty = val_as_f64(g.get("dirtyCount"), 0.0) as i64;
                let dirty_desc = if dirty > 0 {
                    let plural = if dirty == 1 { "" } else { "s" };
                    let files_suffix = match g.get("dirtyFiles").and_then(|v| v.as_array()) {
                        Some(arr) if !arr.is_empty() => {
                            let names: Vec<String> =
                                arr.iter().take(5).map(|x| val_to_string(Some(x))).collect();
                            format!(": {}", names.join(", "))
                        }
                        _ => String::new(),
                    };
                    format!("{dirty} uncommitted file{plural}{files_suffix}")
                } else {
                    "clean working tree".to_string()
                };
                sections.push(format!(
                    "LIVE GIT WORKSPACE: branch {branch}{sha} · {dirty_desc}"
                ));
            }
        }
    }

    if include_github {
        if let Some(gh) = github {
            let repo = val_as_str(gh, "repo")
                .filter(|s| !s.is_empty())
                .unwrap_or("VitruvianSoftware/vitruvian-core");
            let unavailable = gh
                .get("unavailable")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            if unavailable {
                sections.push(
                    "GitHub state unavailable this turn (gh query failed or timed out).\nTreat all remembered PR/issue status as STALE and re-query before reporting it."
                        .to_string(),
                );
            } else {
                let open_lines = match gh.get("openPrs").and_then(|v| v.as_array()) {
                    Some(arr) if !arr.is_empty() => arr
                        .iter()
                        .filter_map(|v| v.as_object())
                        .map(|pr| {
                            let num = val_to_string(pr.get("number"));
                            let draft =
                                if pr.get("isDraft").and_then(|v| v.as_bool()).unwrap_or(false) {
                                    " [draft]"
                                } else {
                                    ""
                                };
                            let title = val_to_string(pr.get("title"));
                            format!("  #{num}{draft} {title}")
                        })
                        .collect::<Vec<_>>()
                        .join("\n"),
                    _ => "  (none)".to_string(),
                };

                let merged_lines = match gh.get("mergedPrs").and_then(|v| v.as_array()) {
                    Some(arr) if !arr.is_empty() => arr
                        .iter()
                        .filter_map(|v| v.as_object())
                        .map(|pr| {
                            let num = val_to_string(pr.get("number"));
                            let title = val_to_string(pr.get("title"));
                            let merged_at = val_as_str(pr, "mergedAt").unwrap_or("");
                            let suffix = if merged_at.is_empty() {
                                String::new()
                            } else {
                                format!("  (merged {merged_at})")
                            };
                            format!("  #{num} {title}{suffix}")
                        })
                        .collect::<Vec<_>>()
                        .join("\n"),
                    _ => "  (none)".to_string(),
                };

                let issue_count = match gh.get("openIssues") {
                    Some(v) if !v.is_null() => val_to_string(Some(v)),
                    _ => "?".to_string(),
                };

                sections.push(format!(
                    "LIVE {repo} state, fetched just now — this SUPERSEDES any PR/issue status stated earlier in this conversation. Do not restate status from earlier turns; if something you are about to report is not reflected here, re-query it.\n\nOPEN PRs:\n{open_lines}\n\nRECENTLY MERGED PRs (last 10):\n{merged_lines}\n\nOPEN issues: {issue_count}"
                ));
            }
        }
    }

    sections.join("\n\n").trim().to_string()
}

/// Builds the Antigravity `PreInvocation` JSON output payload.
pub fn build_ephemeral_context_payload(
    git: Option<&Map<String, Value>>,
    github: Option<&Map<String, Value>>,
    settings: Option<&Map<String, Value>>,
) -> Value {
    let empty = Map::new();
    let s = settings.unwrap_or(&empty);
    let inject_git = s.get("injectGit") != Some(&Value::Bool(false));
    let inject_github = s.get("injectGitHub") != Some(&Value::Bool(false));
    let inject_contract = s.get("injectContract") != Some(&Value::Bool(false));

    let contract_text = match s.get("contractText") {
        Some(v) if !v.is_null() => val_to_string(Some(v)).trim().to_string(),
        _ => DEFAULT_RESPONSE_CONTRACT.trim().to_string(),
    };

    let mut blocks = Vec::new();
    if inject_git || inject_github {
        let empty_git = Map::new();
        let empty_gh = Map::new();
        let live_summary = format_live_git_summary(
            Some(git.unwrap_or(&empty_git)),
            Some(github.unwrap_or(&empty_gh)),
            inject_git,
            inject_github,
        );
        if !live_summary.is_empty() {
            blocks.push(live_summary);
        }
    }

    if inject_contract && !contract_text.is_empty() {
        blocks.push(contract_text);
    }

    if blocks.is_empty() {
        return json!({});
    }

    json!({
        "injectSteps": [
            {
                "ephemeralMessage": blocks.join("\n\n---\n\n")
            }
        ]
    })
}

/// Executes the PreInvocation hook against `state_dir`.
pub fn run_inject_live_context(state_dir: Option<&Path>) -> String {
    let read_json_obj = |name: &str| -> Map<String, Value> {
        let Some(dir) = state_dir else {
            return Map::new();
        };
        let p = dir.join(name);
        let Ok(raw) = fs::read_to_string(p) else {
            return Map::new();
        };
        match serde_json::from_str::<Value>(&raw) {
            Ok(Value::Object(map)) => map,
            _ => Map::new(),
        }
    };

    let settings = read_json_obj("settings.json");
    let snapshot = read_json_obj("snapshot.json");
    let git = snapshot.get("git").and_then(|v| v.as_object());
    let github = snapshot.get("github").and_then(|v| v.as_object());

    let out = build_ephemeral_context_payload(git, github, Some(&settings));
    serde_json::to_string(&out).unwrap_or_else(|_| "{}".to_string())
}

fn strip_fenced_code_blocks(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(start) = rest.find("```") {
        out.push_str(&rest[..start]);
        let after_open = &rest[start + 3..];
        if let Some(end) = after_open.find("```") {
            rest = &after_open[end + 3..];
        } else {
            out.push_str(&rest[start..]);
            return out;
        }
    }
    out.push_str(rest);
    out
}

fn strip_inline_code_and_quotes(s: &str) -> String {
    let chars: Vec<char> = s.chars().collect();
    let mut out = String::with_capacity(s.len());
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        let closing = match c {
            '`' => Some('`'),
            '"' => Some('"'),
            '\'' => Some('\''),
            '\u{201c}' => Some('\u{201d}'),
            _ => None,
        };
        if let Some(close_ch) = closing {
            if let Some(rel_end) = chars[i + 1..].iter().position(|&ch| ch == close_ch) {
                i += 1 + rel_end + 1;
                continue;
            }
        }
        out.push(c);
        i += 1;
    }
    out
}

fn has_word_boundary_after(haystack_lower: &str, needle: &str) -> bool {
    let mut rest = haystack_lower;
    while let Some(idx) = rest.find(needle) {
        let after = &rest[idx + needle.len()..];
        let next_ch = after.chars().next();
        let is_word_char = next_ch
            .map(|c| c.is_ascii_alphanumeric() || c == '_')
            .unwrap_or(false);
        if !is_word_char {
            return true;
        }
        rest = &rest[idx + needle.len()..];
    }
    false
}

fn contains_diagram_marker(msg: &str) -> bool {
    let lower = msg.to_ascii_lowercase();
    lower.contains("show_widget")
        || has_word_boundary_after(&lower, "```mermaid")
        || has_word_boundary_after(&lower, "<agent-embed")
}

#[derive(Debug, Clone, PartialEq)]
pub struct ContractCheckResult {
    pub exempt: bool,
    pub chars: usize,
    pub has_filler: bool,
    pub has_diagram: Option<bool>,
    pub long_no_diagram: bool,
    pub final_line: String,
    pub failures: Vec<String>,
    pub valid: bool,
}

/// Checks an assistant reply against the response shape contract.
pub fn check_response_contract(
    message: &str,
    min_chars: Option<usize>,
    diagram_min_chars: Option<usize>,
) -> ContractCheckResult {
    let msg = message.trim();
    let chars = msg.encode_utf16().count();
    let min_c = min_chars.unwrap_or(300);
    let diag_min_c = diagram_min_chars.unwrap_or(2600);

    if chars < min_c {
        return ContractCheckResult {
            exempt: true,
            chars,
            has_filler: false,
            has_diagram: None,
            long_no_diagram: false,
            final_line: String::new(),
            failures: Vec::new(),
            valid: true,
        };
    }

    let has_diagram = if chars >= diag_min_c {
        Some(contains_diagram_marker(msg))
    } else {
        None
    };
    let long_no_diagram = has_diagram == Some(false);

    let without_code = strip_fenced_code_blocks(msg);
    let raw_last_line = without_code
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .next_back()
        .unwrap_or("")
        .to_string();

    let stripped_last_line = strip_inline_code_and_quotes(&raw_last_line).to_ascii_lowercase();
    let has_filler = FILLER_PHRASES
        .iter()
        .any(|phrase| stripped_last_line.contains(phrase));

    let mut failures = Vec::new();
    if has_filler {
        failures.push(
            "closes with an empty 'nothing needed' line -- end after the detail instead; only add a next step when there is a real one"
                .to_string(),
        );
    }

    let valid = failures.is_empty();
    ContractCheckResult {
        exempt: false,
        chars,
        has_filler,
        has_diagram,
        long_no_diagram,
        final_line: raw_last_line,
        failures,
        valid,
    }
}

fn format_iso8601_now() -> String {
    let dur = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let secs = dur.as_secs() as i64;
    let millis = dur.subsec_millis();

    let days = secs.div_euclid(86_400);
    let rem = secs.rem_euclid(86_400);
    let hour = rem / 3600;
    let minute = (rem % 3600) / 60;
    let second = rem % 60;

    // Civil date from days since 1970-01-01 (Howard Hinnant's algorithm)
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u32;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if m <= 2 { y + 1 } else { y };

    format!("{year:04}-{m:02}-{d:02}T{hour:02}:{minute:02}:{second:02}.{millis:03}Z")
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VerdictLogRecord {
    pub ts: String,
    pub conversation_id: String,
    pub mode: String,
    pub chars: usize,
    pub filler: bool,
    pub diagram: Option<bool>,
    pub long_no_diagram: bool,
    pub verdict: String,
    pub tail: String,
}

#[derive(Debug, Clone)]
pub struct StopEvaluationResult {
    pub output: Value,
    pub bounced: bool,
    pub log_record: Option<VerdictLogRecord>,
}

/// Evaluates an Antigravity `Stop` hook event.
pub fn evaluate_stop_shape(
    stop_event: &Map<String, Value>,
    mode_opt: Option<&str>,
    min_chars: Option<usize>,
    diagram_min_chars: Option<usize>,
    now_iso: Option<&str>,
) -> StopEvaluationResult {
    let mode = if mode_opt == Some("enforce") {
        "enforce"
    } else {
        "log"
    };
    let execution_num = val_as_f64(stop_event.get("executionNum"), 1.0);
    let reason = match stop_event.get("terminationReason") {
        Some(v) if !v.is_null() => val_to_string(Some(v)),
        _ => "NO_TOOL_CALL".to_string(),
    };
    let stop_hook_active = stop_event.get("stopHookActive") == Some(&Value::Bool(true));

    if stop_hook_active || execution_num > 1.0 || (!reason.is_empty() && reason != "NO_TOOL_CALL") {
        return StopEvaluationResult {
            output: json!({ "decision": "allow" }),
            bounced: false,
            log_record: None,
        };
    }

    let last_msg = match stop_event.get("lastAssistantMessage") {
        Some(v) if !v.is_null() => val_to_string(Some(v)),
        _ => String::new(),
    };

    let check = check_response_contract(&last_msg, min_chars, diagram_min_chars);
    if check.exempt {
        return StopEvaluationResult {
            output: json!({ "decision": "allow" }),
            bounced: false,
            log_record: None,
        };
    }

    let msg_trimmed = last_msg.trim();
    let msg_chars: Vec<char> = msg_trimmed.chars().collect();
    let tail_start = msg_chars.len().saturating_sub(120);
    let tail: String = msg_chars[tail_start..]
        .iter()
        .collect::<String>()
        .replace('\n', " ");

    let conv_id_raw = match stop_event.get("conversationId") {
        Some(v) if !v.is_null() => val_to_string(Some(v)),
        _ => String::new(),
    };
    let conv_id: String = conv_id_raw.chars().take(8).collect();
    let ts = now_iso
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .unwrap_or_else(format_iso8601_now);

    let log_record = VerdictLogRecord {
        ts,
        conversation_id: conv_id,
        mode: mode.to_string(),
        chars: check.chars,
        filler: check.has_filler,
        diagram: check.has_diagram,
        long_no_diagram: check.long_no_diagram,
        verdict: if check.valid { "pass" } else { "block" }.to_string(),
        tail,
    };

    if !check.valid && mode == "enforce" {
        return StopEvaluationResult {
            output: json!({
                "decision": "continue",
                "reason": format!(
                    "RESPONSE CONTRACT: {}. Revise once; keep the evidence, cut the padding.",
                    check.failures.join("; ")
                ),
            }),
            bounced: true,
            log_record: Some(log_record),
        };
    }

    StopEvaluationResult {
        output: json!({ "decision": "allow" }),
        bounced: false,
        log_record: Some(log_record),
    }
}

/// Runs the Stop hook against `payload` and `state_dir`.
pub fn run_verify_response_shape(payload: &str, state_dir: Option<&Path>) -> String {
    let Ok(Value::Object(mut ev)) = serde_json::from_str::<Value>(payload) else {
        return r#"{"decision":"allow"}"#.to_string();
    };

    let mut mode = "log".to_string();
    let mut min_chars: Option<usize> = None;

    if let Some(dir) = state_dir {
        let sp = dir.join("settings.json");
        if let Ok(raw) = fs::read_to_string(sp) {
            if let Ok(Value::Object(settings)) = serde_json::from_str::<Value>(&raw) {
                if let Some(m) = val_as_str(&settings, "mode").filter(|s| !s.is_empty()) {
                    mode = m.to_string();
                }
                if let Some(mc) = settings.get("minChars") {
                    let n = val_as_f64(Some(mc), 300.0);
                    if n > 0.0 {
                        min_chars = Some(n as usize);
                    }
                }
            }
        }
    }

    let mut last_assistant_message = match ev.get("lastAssistantMessage") {
        Some(v) if !v.is_null() => val_to_string(Some(v)),
        _ => String::new(),
    };

    if last_assistant_message.is_empty() {
        if let Some(tp) = val_as_str(&ev, "transcriptPath").filter(|s| !s.is_empty()) {
            let p = Path::new(tp);
            if let Ok(content) = fs::read_to_string(p) {
                for line in content.trim().lines().rev() {
                    let Ok(Value::Object(step)) = serde_json::from_str::<Value>(line) else {
                        break;
                    };
                    let step_type = val_as_str(&step, "type").unwrap_or("").to_ascii_uppercase();
                    if step_type == "PLANNER_RESPONSE" {
                        let c = val_to_string(step.get("content"));
                        if !c.is_empty() {
                            last_assistant_message = c;
                            break;
                        }
                    }
                }
            }
        }
    }

    ev.insert(
        "lastAssistantMessage".to_string(),
        Value::String(last_assistant_message),
    );

    let result = evaluate_stop_shape(&ev, Some(&mode), min_chars, None, None);

    if let (Some(log_rec), Some(dir)) = (&result.log_record, state_dir) {
        if !dir.as_os_str().is_empty() && fs::create_dir_all(dir).is_ok() {
            if let Ok(mut file) = OpenOptions::new()
                .create(true)
                .append(true)
                .open(dir.join("verdicts.jsonl"))
            {
                if let Ok(line) = serde_json::to_string(log_rec) {
                    let _ = writeln!(file, "{line}");
                }
            }
        }
    }

    serde_json::to_string(&result.output).unwrap_or_else(|_| r#"{"decision":"allow"}"#.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_git_and_github_summary() {
        let git: Map<String, Value> = serde_json::from_value(json!({
            "branch": "feat/rust",
            "headSha": "abc1234",
            "dirtyCount": 2,
            "dirtyFiles": ["a.rs", "b.rs"]
        }))
        .unwrap();
        let github: Map<String, Value> = serde_json::from_value(json!({
            "repo": "VitruvianSoftware/vitruvian-core",
            "openPrs": [{"number": 42, "title": "Add Rust hooks", "isDraft": true}],
            "mergedPrs": [{"number": 41, "title": "Init", "mergedAt": "2026-10-25"}],
            "openIssues": 3
        }))
        .unwrap();

        let summary = format_live_git_summary(Some(&git), Some(&github), true, true);
        assert!(summary.contains(
            "LIVE GIT WORKSPACE: branch feat/rust (abc1234) · 2 uncommitted files: a.rs, b.rs"
        ));
        assert!(summary.contains("  #42 [draft] Add Rust hooks"));
        assert!(summary.contains("  #41 Init  (merged 2026-10-25)"));
        assert!(summary.contains("OPEN issues: 3"));
    }

    #[test]
    fn detects_filler_closing_line_and_ignores_quoted() {
        let padding = "x".repeat(320);
        let bad = format!("{padding}\nNothing needed from you.");
        let res = check_response_contract(&bad, Some(300), None);
        assert!(!res.valid);
        assert!(res.has_filler);

        let quoted = format!("{padding}\nNever write 'Nothing needed from you.' in replies.");
        let res_quoted = check_response_contract(&quoted, Some(300), None);
        assert!(res_quoted.valid);
        assert!(!res_quoted.has_filler);
    }

    #[test]
    fn enforce_mode_bounces_on_filler() {
        let padding = "x".repeat(320);
        let ev: Map<String, Value> = serde_json::from_value(json!({
            "conversationId": "12345678-aaaa",
            "executionNum": 1,
            "terminationReason": "NO_TOOL_CALL",
            "lastAssistantMessage": format!("{padding}\nNo action is needed.")
        }))
        .unwrap();

        let res = evaluate_stop_shape(
            &ev,
            Some("enforce"),
            Some(300),
            None,
            Some("2026-10-25T00:00:00.000Z"),
        );
        assert!(res.bounced);
        assert_eq!(res.output["decision"], "continue");
        assert_eq!(res.log_record.unwrap().verdict, "block");
    }
}
