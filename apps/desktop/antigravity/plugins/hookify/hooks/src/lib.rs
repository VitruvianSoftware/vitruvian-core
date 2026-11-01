// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

//! The hookify hook: loads declarative rules and evaluates them on
//! `PreToolUse` and `Stop`.
//!
//! This replaced a Node.js script that ran `sidecars/panel/lib/core.mjs`, and
//! keeps its behaviour, including JavaScript's reading of odd input (`||`,
//! `String()`, `RegExp`). The side panel still runs `core.mjs`, so the two
//! must agree; `tests` below pins the cases where they easily would not.
//!
//! The crate uses only the standard library, so `../rust-hook.sh` can build
//! it with a bare `rustc` wherever the plugin is installed.

pub mod json;
pub mod regex;

use json::{obj, Map, Value};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

pub const SUPPORTED_OPERATORS: &[&str] = &[
    "regex_match",
    "contains",
    "not_contains",
    "equals",
    "starts_with",
    "ends_with",
];

pub const SUPPORTED_ACTIONS: &[&str] = &[
    "allow",
    "warn",
    "ask",
    "force_ask",
    "block",
    "deny",
    "overwrite",
];

/// What the hook prints when no rule applies. Antigravity reads a PreToolUse
/// answer without a `decision` (`{}`, which the script printed) as a denial,
/// so every answer carries one.
pub const ALLOW: &str = r#"{"decision":"allow"}"#;

/// The tools that edit files, for `event: file` rules. Antigravity's own
/// (write_to_file, replace_file_content, multi_replace_file_content) come
/// first; the rest are other agents' names the script already knew.
const FILE_TOOLS: &[&str] = &[
    "write_to_file",
    "replace_file_content",
    "multi_replace_file_content",
    "write_file",
    "edit_file",
    "multi_edit",
    "write",
    "edit",
    "replace",
];

// ---- JavaScript coercions -------------------------------------------------

/// JavaScript truthiness.
fn truthy(v: Option<&Value>) -> bool {
    match v {
        None | Some(Value::Null) => false,
        Some(Value::Bool(b)) => *b,
        Some(Value::Number(n)) => *n != 0.0 && !n.is_nan(),
        Some(Value::String(s)) => !s.is_empty(),
        Some(_) => true,
    }
}

/// `String(v)`; `None` is `undefined`.
fn js_string(v: Option<&Value>) -> String {
    match v {
        None => "undefined".to_string(),
        Some(Value::Null) => "null".to_string(),
        Some(Value::Bool(b)) => b.to_string(),
        Some(n @ Value::Number(_)) => n.to_string(),
        Some(Value::String(s)) => s.clone(),
        Some(Value::Array(a)) => a
            .iter()
            .map(|x| {
                if x.is_null() {
                    String::new()
                } else {
                    js_string(Some(x))
                }
            })
            .collect::<Vec<_>>()
            .join(","),
        Some(Value::Object(_)) => "[object Object]".to_string(),
    }
}

/// `String(a || b)`.
fn or_str(a: Option<&Value>, fallback: &str) -> String {
    if truthy(a) {
        js_string(a)
    } else {
        fallback.to_string()
    }
}

/// `v ?? null`, as an `Option` of a non-null value.
fn defined(v: Option<&Value>) -> Option<&Value> {
    v.filter(|v| !v.is_null())
}

/// `String.prototype.trim`.
fn js_trim(s: &str) -> &str {
    s.trim_matches(|c: char| c.is_whitespace() || c == '\u{FEFF}')
}

/// `typeof v === "object"` for a non-null value (arrays included).
fn is_js_object(v: Option<&Value>) -> bool {
    matches!(v, Some(Value::Object(_) | Value::Array(_)))
}

/// The members of a JavaScript object value, as `{...v}` would see them.
fn spread(v: Option<&Value>) -> Map {
    match v {
        Some(Value::Object(m)) => m.clone(),
        Some(Value::Array(a)) => a
            .iter()
            .enumerate()
            .map(|(i, x)| (i.to_string(), x.clone()))
            .collect(),
        _ => Map::new(),
    }
}

/// The tool call's arguments: `toolCall.args`, else `tool_input`.
fn tool_args(p: &Map) -> Map {
    let args = p.get("toolCall").and_then(|tc| tc.get("args"));
    if truthy(args) && is_js_object(args) {
        return spread(args);
    }
    let input = p.get("tool_input");
    if truthy(input) && is_js_object(input) {
        return spread(input);
    }
    Map::new()
}

// ---- Markdown rules -------------------------------------------------------

fn strip_quotes(val: &str) -> String {
    let trimmed = js_trim(val);
    let quoted = trimmed.len() >= 2
        && ((trimmed.starts_with('"') && trimmed.ends_with('"'))
            || (trimmed.starts_with('\'') && trimmed.ends_with('\'')));
    // JavaScript also strips a lone quote character ('"'.slice(1, -1)).
    if quoted || trimmed == "\"" || trimmed == "'" {
        let inner = if trimmed.len() >= 2 {
            &trimmed[1..trimmed.len() - 1]
        } else {
            ""
        };
        return inner
            .replace("\\\"", "\"")
            .replace("\\\\", "\\")
            .replace("\\n", "\n")
            .replace("\\t", "\t");
    }
    trimmed.to_string()
}

/// `/^-?\d+(\.\d+)?$/`.
fn is_js_number_literal(s: &str) -> bool {
    let s = s.strip_prefix('-').unwrap_or(s);
    let (int, frac) = match s.split_once('.') {
        Some((i, f)) => (i, Some(f)),
        None => (s, None),
    };
    !int.is_empty()
        && int.bytes().all(|b| b.is_ascii_digit())
        && frac.map_or(true, |f| {
            !f.is_empty() && f.bytes().all(|b| b.is_ascii_digit())
        })
}

fn parse_scalar(raw: &str) -> Value {
    let s = js_trim(raw);
    match s {
        "true" => Value::Bool(true),
        "false" => Value::Bool(false),
        "null" => Value::Null,
        _ if is_js_number_literal(s) => Value::Number(s.parse().unwrap_or(f64::NAN)),
        _ => Value::String(strip_quotes(s)),
    }
}

/// `/^([A-Za-z0-9_-]+)\s*:\s*(.*)$/` (map keys also allow `.`).
fn split_yaml_kv(line: &str, allow_dot: bool) -> Option<(&str, &str)> {
    let key_len = line
        .bytes()
        .take_while(|b| {
            b.is_ascii_alphanumeric() || *b == b'_' || *b == b'-' || (allow_dot && *b == b'.')
        })
        .count();
    if key_len == 0 {
        return None;
    }
    let rest = line[key_len..].trim_start_matches(|c: char| c.is_whitespace() || c == '\u{FEFF}');
    let rest = rest.strip_prefix(':')?;
    let rest = rest.trim_start_matches(|c: char| c.is_whitespace() || c == '\u{FEFF}');
    // `.` does not match line terminators, so such a value is no match.
    if rest.contains(['\r', '\u{2028}', '\u{2029}']) {
        return None;
    }
    Some((&line[..key_len], rest))
}

/// Parses a `.agents/hookify.<name>.md` markdown document with YAML frontmatter.
pub fn parse_hookify_markdown(markdown: &str, source_path: &str) -> Option<Value> {
    let text = markdown.replace("\r\n", "\n");
    // /^---\n([\s\S]*?)\n---\n?([\s\S]*)$/: the frontmatter ends at the first
    // "\n---", even one that starts a longer line.
    let after_open = text.strip_prefix("---\n")?;
    let idx = after_open.find("\n---")?;
    let frontmatter = &after_open[..idx];
    let rest = &after_open[idx + 4..];
    let body = js_trim(rest.strip_prefix('\n').unwrap_or(rest));

    let mut meta = Map::new();
    let mut current_list_key: Option<String> = None;
    let mut current_map_key: Option<String> = None;

    for raw_line in frontmatter.split('\n') {
        let line = js_trim(raw_line);
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let indented = raw_line.starts_with(|c: char| c.is_whitespace() || c == '\u{FEFF}');

        if !indented {
            current_list_key = None;
            current_map_key = None;
            let Some((key, rest)) = split_yaml_kv(line, false) else {
                continue;
            };
            if rest.is_empty() {
                if key == "conditions" {
                    meta.insert(key, Value::Array(Vec::new()));
                    current_list_key = Some(key.to_string());
                } else {
                    meta.insert(key, Value::Object(Map::new()));
                    current_map_key = Some(key.to_string());
                }
            } else {
                meta.insert(key, parse_scalar(rest));
            }
            continue;
        }

        if let Some(list_key) = &current_list_key {
            let Some(Value::Array(arr)) = meta.get_mut(list_key) else {
                continue;
            };
            if let Some(after_dash) = line.strip_prefix("- ") {
                let mut item = Map::new();
                if let Some((k, v)) = split_yaml_kv(js_trim(after_dash), false) {
                    item.insert(k, parse_scalar(v));
                }
                arr.push(Value::Object(item));
            } else if let Some((k, v)) = split_yaml_kv(line, false) {
                if let Some(Value::Object(last_item)) = arr.last_mut() {
                    last_item.insert(k, parse_scalar(v));
                }
            }
            continue;
        }

        if let Some(map_key) = &current_map_key {
            if let Some((k, v)) = split_yaml_kv(line, true) {
                if let Some(Value::Object(map_obj)) = meta.get_mut(map_key) {
                    map_obj.insert(k, parse_scalar(v));
                }
            }
        }
    }

    let fallback_name = if source_path.is_empty() {
        "unnamed-rule".to_string()
    } else {
        let base = source_path.rsplit('/').next().unwrap_or("");
        let base = base.strip_prefix("hookify.").unwrap_or(base);
        base.strip_suffix(".md").unwrap_or(base).to_string()
    };

    let name = js_trim(&or_str(meta.get("name"), &fallback_name)).to_string();
    let event = js_trim(&or_str(meta.get("event"), "PreToolUse")).to_string();
    let action = js_trim(&or_str(meta.get("action"), "warn")).to_lowercase();
    let enabled = meta.get("enabled") != Some(&Value::Bool(false));

    let mut conditions: Vec<Value> = meta
        .get("conditions")
        .and_then(Value::as_array)
        .map(|arr| arr.iter().filter(|c| c.is_object()).cloned().collect())
        .unwrap_or_default();

    if conditions.is_empty() {
        // `meta.pattern !== undefined`: a `pattern: null` line counts.
        if let Some(pat) = meta.get("pattern") {
            let default_field = if event.to_lowercase() == "file" {
                "Content"
            } else {
                "CommandLine"
            };
            conditions.push(obj([
                (
                    "field",
                    Value::from(or_str(meta.get("field"), default_field)),
                ),
                (
                    "operator",
                    Value::from(or_str(meta.get("operator"), "regex_match")),
                ),
                ("pattern", Value::from(js_string(Some(pat)))),
            ]));
        }
    }

    let id = or_str(meta.get("id"), &name);
    let tool = if truthy(meta.get("tool")) {
        js_string(meta.get("tool"))
    } else if truthy(meta.get("matcher")) {
        js_string(meta.get("matcher"))
    } else {
        "*".to_string()
    };
    let message = if !body.is_empty() {
        body.to_string()
    } else {
        or_str(meta.get("message"), &format!("Rule '{name}' triggered."))
    };

    let mut out = Map::new();
    out.insert("id", id);
    out.insert("name", name);
    out.insert("enabled", enabled);
    out.insert("event", event);
    out.insert("tool", tool);
    out.insert("action", action);
    out.insert("conditions", Value::Array(conditions));
    if let Some(ow @ Value::Object(_)) = meta.get("overwrite") {
        out.insert("overwrite", ow.clone());
    }
    out.insert("message", message);
    out.insert(
        "source",
        if source_path.is_empty() {
            "markdown"
        } else {
            source_path
        },
    );
    Some(Value::Object(out))
}

/// Serializes a Hookify rule object back to `.agents/hookify.<name>.md` markdown.
pub fn serialize_hookify_markdown(rule: &Value) -> String {
    let empty = Map::new();
    let r = rule.as_object().unwrap_or(&empty);
    let name = if truthy(r.get("name")) {
        js_string(r.get("name"))
    } else {
        or_str(r.get("id"), "unnamed-rule")
    };
    let enabled = r.get("enabled") != Some(&Value::Bool(false));
    let event = or_str(r.get("event"), "PreToolUse");
    let action = or_str(r.get("action"), "warn");
    let tool = if truthy(r.get("tool")) {
        js_string(r.get("tool"))
    } else {
        or_str(r.get("matcher"), "*")
    };

    let mut lines = vec![
        "---".to_string(),
        format!("name: {name}"),
        format!("enabled: {enabled}"),
        format!("event: {event}"),
    ];
    if !tool.is_empty() && tool != "*" {
        lines.push(format!("tool: {tool}"));
    }
    lines.push(format!("action: {action}"));

    let conditions = r
        .get("conditions")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    if !conditions.is_empty() {
        lines.push("conditions:".to_string());
        for c in &conditions {
            if !is_js_object(Some(c)) {
                continue;
            }
            let pat = Value::from(js_string(Some(
                defined(c.get("pattern")).unwrap_or(&Value::from("")),
            )));
            lines.push(format!(
                "  - field: {}",
                or_str(c.get("field"), "CommandLine")
            ));
            lines.push(format!(
                "    operator: {}",
                or_str(c.get("operator"), "regex_match")
            ));
            lines.push(format!("    pattern: {pat}"));
        }
    } else if truthy(r.get("pattern")) {
        lines.push(format!(
            "pattern: {}",
            Value::from(js_string(r.get("pattern")))
        ));
    }

    if let Some(Value::Object(ow)) = r.get("overwrite") {
        lines.push("overwrite:".to_string());
        for (k, v) in ow.iter() {
            lines.push(format!("  {k}: {v}"));
        }
    }

    lines.push("---".to_string());
    let msg = or_str(r.get("message"), &format!("Rule '{name}' triggered."));
    lines.push(js_trim(&msg).to_string());
    lines.push(String::new());
    lines.join("\n")
}

// ---- Evaluating rules -----------------------------------------------------

/// Extracts a logical field from an Antigravity or Claude Code hook payload.
pub fn extract_field_from_payload(payload: &Value, field: &str) -> String {
    let empty = Map::new();
    let p = payload.as_object().unwrap_or(&empty);
    let args = tool_args(p);
    // `String(field || "CommandLine").trim()`.
    let key = js_trim(if field.is_empty() {
        "CommandLine"
    } else {
        field
    });
    let lower = key.to_lowercase();

    if let Some(v) = defined(args.get(key)) {
        return js_string(Some(v));
    }
    if let Some(v) = defined(p.get(key)) {
        return if is_js_object(Some(v)) {
            v.to_string()
        } else {
            js_string(Some(v))
        };
    }

    // `String(a ?? b ?? ... ?? "")`.
    let first = |candidates: &[Option<&Value>]| -> String {
        candidates
            .iter()
            .find_map(|c| defined(*c))
            .map(|v| js_string(Some(v)))
            .unwrap_or_default()
    };

    match lower.as_str() {
        "command" | "commandline" | "cmd" => first(&[
            args.get("CommandLine"),
            args.get("command"),
            p.get("command"),
        ]),
        "file_path" | "filepath" | "path" | "file" => first(&[
            args.get("Path"),
            args.get("file_path"),
            args.get("path"),
            p.get("file_path"),
            args.get("TargetFile"),
            args.get("AbsolutePath"),
        ]),
        "content" | "new_text" | "replacement" => {
            let chunks = chunk_text(&args, "ReplacementContent");
            first(&[
                args.get("Content"),
                args.get("Replacement"),
                args.get("content"),
                args.get("new_string"),
                args.get("new_str"),
                args.get("CodeContent"),
                args.get("ReplacementContent"),
                chunks.as_ref(),
            ])
        }
        "target" | "old_text" | "old_string" => {
            let chunks = chunk_text(&args, "TargetContent");
            first(&[
                args.get("Target"),
                args.get("old_string"),
                args.get("old_str"),
                args.get("TargetContent"),
                chunks.as_ref(),
            ])
        }
        "tool" | "tool_name" | "toolname" => first(&[
            p.get("toolCall").and_then(|tc| tc.get("name")),
            p.get("tool_name"),
        ]),
        "reason" | "stop_reason" | "transcript" => first(&[
            p.get("reason"),
            p.get("stop_reason"),
            p.get("transcript"),
            p.get("lastMessage"),
        ]),
        _ => String::new(),
    }
}

/// `multi_replace_file_content` edits: `key` of every `ReplacementChunks`
/// entry, one per line.
fn chunk_text(args: &Map, key: &str) -> Option<Value> {
    let chunks = args.get("ReplacementChunks")?.as_array()?;
    let parts: Vec<String> = chunks
        .iter()
        .filter_map(|c| defined(c.get(key)))
        .map(|v| js_string(Some(v)))
        .collect();
    (!parts.is_empty()).then(|| Value::from(parts.join("\n")))
}

/// `new RegExp(pattern, flags).test(value)`; a bad pattern never matches.
fn regex_test(pattern: &str, ignore_case: bool, value: &str) -> Option<bool> {
    regex::Regex::new(pattern, ignore_case)
        .ok()
        .map(|re| re.test(value))
}

/// Evaluates a single condition against a hook payload.
pub fn evaluate_condition(condition: &Value, payload: &Value) -> bool {
    let Some(cond) = condition.as_object() else {
        return false;
    };
    let field = or_str(cond.get("field"), "CommandLine");
    let operator = js_trim(&or_str(cond.get("operator"), "regex_match")).to_lowercase();
    let pattern = defined(cond.get("pattern"))
        .map(|v| js_string(Some(v)))
        .unwrap_or_default();
    let raw_value = extract_field_from_payload(payload, &field);
    let case_sensitive = cond.get("caseSensitive") == Some(&Value::Bool(true));

    let (value, target) = if case_sensitive {
        (raw_value.clone(), pattern.clone())
    } else {
        (raw_value.to_lowercase(), pattern.to_lowercase())
    };

    match operator.as_str() {
        "regex_match" => regex_test(&pattern, !case_sensitive, &raw_value).unwrap_or(false),
        "contains" => value.contains(&target),
        "not_contains" => !value.contains(&target),
        "equals" => value == target,
        "starts_with" => value.starts_with(&target),
        "ends_with" => value.ends_with(&target),
        _ => false,
    }
}

fn matches_event_and_tool(rule: &Map, payload: &Value, phase: &str) -> bool {
    let rule_event = js_trim(&or_str(rule.get("event"), "PreToolUse")).to_lowercase();
    // `String(payload?.toolCall?.name ?? payload?.tool_name ?? "").trim()`.
    let tool_name = payload
        .get("toolCall")
        .and_then(|tc| defined(tc.get("name")))
        .or_else(|| defined(payload.get("tool_name")))
        .map(|v| js_trim(&js_string(Some(v))).to_string())
        .unwrap_or_default();

    if phase == "Stop" {
        return rule_event == "stop" || rule_event == "all" || rule_event == "*";
    }

    if rule_event == "stop" {
        return false;
    }
    let tool_lower = tool_name.to_lowercase();
    if rule_event == "bash" {
        if !tool_name.is_empty()
            && !matches!(
                tool_lower.as_str(),
                "run_command" | "bash" | "execute_command"
            )
        {
            return false;
        }
    } else if rule_event == "file"
        && !tool_name.is_empty()
        && !FILE_TOOLS.contains(&tool_lower.as_str())
    {
        return false;
    }

    let matcher_raw = if truthy(rule.get("tool")) {
        js_string(rule.get("tool"))
    } else {
        or_str(rule.get("matcher"), "*")
    };
    let matcher = js_trim(&matcher_raw);
    if matcher.is_empty() || matcher == "*" || matcher.to_lowercase() == "all" {
        return true;
    }
    if tool_name.is_empty() {
        return false;
    }
    match regex_test(&format!("^({matcher})$"), true, &tool_name) {
        Some(m) => m,
        None => matcher.to_lowercase() == tool_lower,
    }
}

fn normalize_decision(action: &str) -> &'static str {
    match js_trim(action).to_lowercase().as_str() {
        "block" | "deny" => "deny",
        "force_ask" => "force_ask",
        "warn" | "ask" => "ask",
        "overwrite" => "overwrite",
        "allow" => "allow",
        _ => "ask",
    }
}

fn decision_rank(decision: &str) -> u8 {
    match decision {
        "allow" => 1,
        "overwrite" => 2,
        "ask" => 3,
        "force_ask" => 4,
        "deny" => 5,
        _ => 0,
    }
}

fn compute_overwritten_input(rule: &Map, current_args: &Map) -> Map {
    let mut args = current_args.clone();
    let Some(spec_val) = rule
        .get("overwrite")
        .filter(|v| truthy(Some(v)) && is_js_object(Some(v)))
    else {
        return args;
    };
    let spec = spread(Some(spec_val));

    // `typeof field === "string" && typeof find === "string" && replace !== undefined`:
    // a `replace: null` counts, and becomes "null".
    if let (Some(Value::String(field_name)), Some(Value::String(find)), Some(replace)) =
        (spec.get("field"), spec.get("find"), spec.get("replace"))
    {
        let prev = defined(args.get(field_name))
            .map(|v| js_string(Some(v)))
            .unwrap_or_default();
        let replace = js_string(Some(replace));
        let updated = match regex::Regex::new(find, false) {
            Ok(re) => re.replace_all(&prev, &replace),
            Err(_) => regex::replace_all_literal(&prev, find, &replace),
        };
        args.insert(field_name.clone(), updated);
        return args;
    }

    for (k, v) in spec.iter() {
        args.insert(k.clone(), v.clone());
    }
    args
}

#[derive(Debug, Clone, PartialEq)]
pub struct RuleEvalResult {
    pub matched: bool,
    pub rule_id: String,
    pub rule_name: String,
    pub action: String,
    pub decision: String,
    pub message: String,
    pub updated_input: Option<Map>,
}

/// Evaluates a single Hookify rule against a payload.
pub fn evaluate_rule(rule: &Value, payload: &Value, phase: &str) -> RuleEvalResult {
    let empty = Map::new();
    let r = rule.as_object().unwrap_or(&empty);
    let rule_id = if truthy(r.get("id")) {
        js_string(r.get("id"))
    } else {
        or_str(r.get("name"), "unnamed")
    };
    let rule_name = or_str(r.get("name"), &rule_id);
    let action = or_str(r.get("action"), "warn").to_lowercase();
    let decision = normalize_decision(&action).to_string();
    let message = or_str(r.get("message"), &format!("Rule '{rule_name}' matched."));

    let unmatched = RuleEvalResult {
        matched: false,
        rule_id: rule_id.clone(),
        rule_name: rule_name.clone(),
        action: action.clone(),
        decision: decision.clone(),
        message: message.clone(),
        updated_input: None,
    };

    if r.get("enabled") == Some(&Value::Bool(false)) || !matches_event_and_tool(r, payload, phase) {
        return unmatched;
    }

    let conditions: Vec<Value> = match r.get("conditions").and_then(Value::as_array) {
        Some(arr) if !arr.is_empty() => arr.clone(),
        _ if truthy(r.get("pattern")) => {
            let default_field = if phase == "Stop" {
                "reason"
            } else {
                "CommandLine"
            };
            vec![obj([
                ("field", Value::from(or_str(r.get("field"), default_field))),
                (
                    "operator",
                    Value::from(or_str(r.get("operator"), "regex_match")),
                ),
                ("pattern", r["pattern"].clone()),
            ])]
        }
        _ => Vec::new(),
    };

    if conditions.is_empty() || !conditions.iter().all(|c| evaluate_condition(c, payload)) {
        return unmatched;
    }

    let updated_input = (decision == "overwrite").then(|| {
        let p = payload.as_object().unwrap_or(&empty);
        compute_overwritten_input(r, &tool_args(p))
    });

    RuleEvalResult {
        matched: true,
        rule_id,
        rule_name,
        action,
        decision,
        message,
        updated_input,
    }
}

#[derive(Debug, Clone)]
pub struct PreToolEvalSummary {
    pub decision: String,
    pub permission_decision: String,
    pub reason: String,
    pub matched_rules: Vec<RuleEvalResult>,
    pub updated_input: Option<Map>,
    pub hook_output_json: String,
}

/// Evaluates a list of Hookify rules for a `PreToolUse` hook event.
pub fn evaluate_pre_tool_use(rules: &[Value], payload: &Value) -> PreToolEvalSummary {
    let empty = Map::new();
    let mut current_args = tool_args(payload.as_object().unwrap_or(&empty));
    let mut matched_rules = Vec::new();
    let mut has_overwrite = false;

    for rule in rules {
        let res = evaluate_rule(rule, payload, "PreToolUse");
        if res.matched {
            if res.decision == "overwrite" && res.updated_input.is_some() {
                current_args =
                    compute_overwritten_input(rule.as_object().unwrap_or(&empty), &current_args);
                has_overwrite = true;
            }
            matched_rules.push(res);
        }
    }

    if matched_rules.is_empty() {
        return PreToolEvalSummary {
            decision: "allow".to_string(),
            permission_decision: "allow".to_string(),
            reason: String::new(),
            matched_rules,
            updated_input: None,
            hook_output_json: ALLOW.to_string(),
        };
    }

    let mut winning = "allow".to_string();
    for m in &matched_rules {
        if decision_rank(&m.decision) > decision_rank(&winning) {
            winning = m.decision.clone();
        }
    }

    let reason = matched_rules
        .iter()
        .map(|m| format!("[{}] {}", m.rule_name, m.message))
        .collect::<Vec<_>>()
        .join("\n\n");
    let permission_decision = if winning == "overwrite" {
        "allow".to_string()
    } else {
        winning.clone()
    };
    let updated_input = (has_overwrite && permission_decision != "deny").then_some(current_args);

    let mut specific = Map::new();
    specific.insert("hookEventName", "PreToolUse");
    specific.insert("permissionDecision", permission_decision.as_str());
    specific.insert("permissionDecisionReason", reason.as_str());
    // Antigravity reads `decision`, `reason` and `overwrite` (a shallow merge
    // into the tool's arguments); the Claude Code keys stay for other hosts.
    let mut out = Map::new();
    out.insert("decision", permission_decision.as_str());
    out.insert("reason", reason.as_str());
    if let Some(ui) = &updated_input {
        out.insert("overwrite", ui.clone());
    }
    out.insert("permissionDecision", permission_decision.as_str());
    out.insert("permissionDecisionReason", reason.as_str());
    if let Some(ui) = &updated_input {
        specific.insert("updatedInput", ui.clone());
        out.insert("updatedInput", ui.clone());
    }
    out.insert("hookSpecificOutput", specific);

    PreToolEvalSummary {
        decision: winning,
        permission_decision,
        reason,
        matched_rules,
        updated_input,
        hook_output_json: Value::Object(out).to_string(),
    }
}

#[derive(Debug, Clone)]
pub struct StopEvalSummary {
    pub continue_flag: bool,
    pub stop_reason: String,
    pub system_message: String,
    pub matched_rules: Vec<RuleEvalResult>,
    pub hook_output_json: String,
}

/// Evaluates a list of Hookify rules for a `Stop` hook event.
pub fn evaluate_stop(rules: &[Value], payload: &Value) -> StopEvalSummary {
    let matched_rules: Vec<RuleEvalResult> = rules
        .iter()
        .map(|rule| evaluate_rule(rule, payload, "Stop"))
        .filter(|r| r.matched)
        .collect();

    if matched_rules.is_empty() {
        return StopEvalSummary {
            continue_flag: true,
            stop_reason: String::new(),
            system_message: String::new(),
            matched_rules,
            hook_output_json: ALLOW.to_string(),
        };
    }

    let message = matched_rules
        .iter()
        .map(|m| format!("[{}] {}", m.rule_name, m.message))
        .collect::<Vec<_>>()
        .join("\n\n");

    if matched_rules.iter().any(|m| m.decision == "deny") {
        let out = obj([
            ("continue", Value::from(false)),
            ("decision", Value::from("block")),
            ("stopReason", Value::from(message.as_str())),
            ("reason", Value::from(message.as_str())),
            ("systemMessage", Value::from(message.as_str())),
        ]);
        return StopEvalSummary {
            continue_flag: false,
            stop_reason: message.clone(),
            system_message: message,
            matched_rules,
            hook_output_json: out.to_string(),
        };
    }

    let out = obj([
        ("decision", Value::from("allow")),
        ("continue", Value::from(true)),
        ("systemMessage", Value::from(message.as_str())),
    ]);
    StopEvalSummary {
        continue_flag: true,
        stop_reason: String::new(),
        system_message: message,
        matched_rules,
        hook_output_json: out.to_string(),
    }
}

// ---- The hook -------------------------------------------------------------

/// Resolves the app data directory from `ANTIGRAVITY_APP_DATA_DIR` or `HOME`.
pub fn resolve_app_dir(app_data_dir: Option<&str>, home_dir: Option<&str>) -> Option<PathBuf> {
    if let Some(dir) = app_data_dir.filter(|s| !s.is_empty()) {
        return Some(PathBuf::from(dir));
    }
    let home = home_dir.filter(|s| !s.is_empty())?;
    Some(Path::new(home).join(".gemini").join("antigravity"))
}

/// Five base-36 characters, standing in for the script's `Math.random()`.
fn random_suffix() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.subsec_nanos() as u64)
        .unwrap_or(0);
    let mut x = nanos ^ (std::process::id() as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15);
    let mut s = String::new();
    for _ in 0..5 {
        let d = (x % 36) as u32;
        s.push(char::from_digit(d, 36).unwrap_or('0'));
        x /= 36;
    }
    s
}

/// The `.agents/hookify.*.md` rules in `cwd`, in name order.
fn load_markdown_rules(cwd: &Path) -> Vec<Value> {
    let agents_dir = cwd.join(".agents");
    let Ok(entries) = fs::read_dir(&agents_dir) else {
        return Vec::new();
    };
    // /^hookify\..+\.md$/
    let mut names: Vec<String> = entries
        .filter_map(|e| e.ok())
        .filter_map(|e| e.file_name().into_string().ok())
        .filter(|n| {
            n.len() > "hookify..md".len()
                && n.starts_with("hookify.")
                && n.ends_with(".md")
                && !n.contains(['\n', '\r', '\u{2028}', '\u{2029}'])
        })
        .collect();
    names.sort_by(|a, b| a.encode_utf16().cmp(b.encode_utf16()));
    let mut rules = Vec::new();
    for name in names {
        let full = agents_dir.join(&name);
        // The script stopped at the first file it could not read.
        let Ok(md) = fs::read_to_string(&full) else {
            break;
        };
        if let Some(rule) = parse_hookify_markdown(&md, &full.to_string_lossy()) {
            rules.push(rule);
        }
    }
    rules
}

/// Evaluates the full Hookify hook against `payload_str` and `app_dir`.
///
/// Every answer has a `decision`: Antigravity's (`allow`, `ask`,
/// `force_ask`, `deny`, plus `overwrite`) next to the Claude Code keys the
/// script printed. A blocking Stop rule still answers `decision: "block"`,
/// which Antigravity treats as letting the turn end.
pub fn handle_hookify_payload(payload_str: &str, app_dir: Option<&Path>) -> String {
    handle_at(payload_str, app_dir, env::current_dir().ok())
}

fn handle_at(payload_str: &str, app_dir: Option<&Path>, process_cwd: Option<PathBuf>) -> String {
    if payload_str.is_empty() {
        return ALLOW.to_string();
    }
    let payload = match json::parse(payload_str) {
        // An array reads as an object with no fields we look at.
        Ok(Value::Array(_)) => Value::Object(Map::new()),
        Ok(v @ Value::Object(_)) => v,
        // `"x" in payload` throws for anything else.
        _ => return ALLOW.to_string(),
    };
    let p = payload.as_object().cloned().unwrap_or_default();

    let mut rules: Vec<Value> = Vec::new();
    if let Some(dir) = app_dir {
        if let Some(parsed) = fs::read_to_string(dir.join("hookify-rules.json"))
            .ok()
            .and_then(|raw| json::parse(&raw).ok())
        {
            if let Some(arr) = parsed.as_array() {
                rules.extend(arr.iter().cloned());
            } else if let Some(arr) = parsed.get("rules").and_then(Value::as_array) {
                rules.extend(arr.iter().cloned());
            }
        }
    }

    // `payload?.toolCall?.args?.Cwd || payload?.cwd || process.cwd()`.
    let cwd_val = p
        .get("toolCall")
        .and_then(|tc| tc.get("args"))
        .and_then(|a| a.get("Cwd"))
        .filter(|v| truthy(Some(v)))
        .or_else(|| p.get("cwd").filter(|v| truthy(Some(v))));
    let cwd = match cwd_val {
        Some(Value::String(s)) => Some(PathBuf::from(s)),
        // path.join throws on a non-string.
        Some(_) => return ALLOW.to_string(),
        None => process_cwd,
    };
    if let Some(cwd) = cwd {
        rules.extend(load_markdown_rules(&cwd));
    }

    let is_stop = p.get("hook_event_name") == Some(&Value::from("Stop"))
        || p.get("event") == Some(&Value::from("Stop"))
        || (!truthy(p.get("toolCall"))
            && !truthy(p.get("tool_name"))
            && (p.contains_key("stop_hook_active") || p.contains_key("reason")));

    let (matched_rules, decision, reason, hook_output) = if is_stop {
        let res = evaluate_stop(&rules, &payload);
        let dec = if res.continue_flag { "warn" } else { "deny" };
        let rsn = if !res.stop_reason.is_empty() {
            res.stop_reason
        } else {
            res.system_message
        };
        (
            res.matched_rules,
            dec.to_string(),
            rsn,
            res.hook_output_json,
        )
    } else {
        let res = evaluate_pre_tool_use(&rules, &payload);
        (
            res.matched_rules,
            res.decision,
            res.reason,
            res.hook_output_json,
        )
    };

    if !matched_rules.is_empty() {
        if let Some(dir) = app_dir {
            record_event(dir, &p, is_stop, &decision, &matched_rules, &reason);
        }
    }

    hook_output
}

/// Prepends an audit event to `hookify-events.json` (newest first, at most
/// 100). Like the script, it leaves a file it cannot parse untouched.
fn record_event(
    dir: &Path,
    p: &Map,
    is_stop: bool,
    decision: &str,
    matched: &[RuleEvalResult],
    reason: &str,
) {
    if fs::create_dir_all(dir).is_err() {
        return;
    }
    let events_file = dir.join("hookify-events.json");
    let existing = match fs::read_to_string(&events_file) {
        Err(_) => Vec::new(),
        Ok(raw) => match json::parse(&raw) {
            Ok(Value::Array(a)) => a,
            // `JSON.parse(...) || []`, then non-arrays count as empty.
            Ok(_) => Vec::new(),
            Err(_) => return,
        },
    };

    let tool = p
        .get("toolCall")
        .and_then(|tc| tc.get("name"))
        .filter(|v| truthy(Some(v)))
        .or_else(|| p.get("tool_name").filter(|v| truthy(Some(v))))
        .cloned()
        .unwrap_or_else(|| Value::from(if is_stop { "Stop" } else { "unknown" }));
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    let event = obj([
        ("id", Value::from(format!("{ts}-{}", random_suffix()))),
        ("timestamp", Value::from(ts)),
        (
            "event",
            Value::from(if is_stop { "Stop" } else { "PreToolUse" }),
        ),
        ("tool", tool),
        ("decision", Value::from(decision)),
        (
            "rules",
            Value::Array(
                matched
                    .iter()
                    .map(|r| {
                        Value::from(if r.rule_name.is_empty() {
                            r.rule_id.as_str()
                        } else {
                            r.rule_name.as_str()
                        })
                    })
                    .collect(),
            ),
        ),
        ("reason", Value::from(reason)),
    ]);

    let mut next = Vec::with_capacity(existing.len() + 1);
    next.push(event);
    next.extend(existing);
    next.truncate(100);
    let tmp = dir.join("hookify-events.json.tmp");
    if fs::write(&tmp, Value::Array(next).to_string_pretty()).is_ok() {
        let _ = fs::rename(&tmp, &events_file);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(src: &str) -> Value {
        json::parse(src).expect("test JSON")
    }

    fn temp_dir(name: &str) -> PathBuf {
        let dir = env::temp_dir().join(format!(
            "hookify-{name}-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    // ---- Ported from core.test.mjs (the panel's copy of this logic) -------

    #[test]
    fn parses_markdown_and_round_trips() {
        let md = "---\nname: block-rm-rf\nenabled: true\nevent: bash\ntool: run_command\naction: block\nconditions:\n  - field: CommandLine\n    operator: regex_match\n    pattern: \"rm\\\\s+-rf\\\\s+/\"\n  - field: CommandLine\n    operator: not_contains\n    pattern: \"--dry-run\"\n---\nDo not run destructive `rm -rf /` commands.\n";
        let rule = parse_hookify_markdown(md, ".agents/hookify.block-rm-rf.md").unwrap();
        assert_eq!(rule["name"], "block-rm-rf");
        assert_eq!(rule["enabled"], true);
        assert_eq!(rule["event"], "bash");
        assert_eq!(rule["tool"], "run_command");
        assert_eq!(rule["action"], "block");
        assert_eq!(
            rule["conditions"][0].to_string(),
            r#"{"field":"CommandLine","operator":"regex_match","pattern":"rm\\s+-rf\\s+/"}"#
        );
        assert_eq!(rule["conditions"].as_array().unwrap().len(), 2);
        assert_eq!(
            rule["message"],
            "Do not run destructive `rm -rf /` commands."
        );

        let serialized = serialize_hookify_markdown(&rule);
        let reparsed = parse_hookify_markdown(&serialized, "").unwrap();
        assert_eq!(reparsed["name"], rule["name"].as_str().unwrap());
        assert_eq!(reparsed["conditions"], rule["conditions"]);
    }

    #[test]
    fn shorthand_pattern_defaults_and_round_trips() {
        let md = "---\nname: warn-console-log\nenabled: false\nevent: file\naction: warn\npattern: \"console\\\\.log\\\\(\"\n---\nAvoid committing debug console.log calls.\n";
        let parsed = parse_hookify_markdown(md, "").unwrap();
        assert_eq!(parsed["enabled"], false);
        assert_eq!(parsed["conditions"][0]["field"], "Content");
        let reparsed = parse_hookify_markdown(&serialize_hookify_markdown(&parsed), "").unwrap();
        for k in ["name", "enabled", "action", "conditions", "message"] {
            assert_eq!(reparsed[k], parsed[k], "{k}");
        }
    }

    #[test]
    fn evaluates_all_six_operators() {
        assert_eq!(SUPPORTED_OPERATORS.len(), 6);
        assert!(SUPPORTED_ACTIONS.contains(&"overwrite"));
        let payload = v(
            r#"{"toolCall":{"name":"run_command","args":{"CommandLine":"git push --force origin main","Path":"/workspace/src/index.ts"}}}"#,
        );
        for cond in [
            r#"{"field":"CommandLine","operator":"regex_match","pattern":"git\\s+push.*--force"}"#,
            r#"{"field":"CommandLine","operator":"contains","pattern":"--force"}"#,
            r#"{"field":"CommandLine","operator":"not_contains","pattern":"--force-with-lease"}"#,
            r#"{"field":"Path","operator":"equals","pattern":"/workspace/src/index.ts"}"#,
            r#"{"field":"CommandLine","operator":"starts_with","pattern":"git push"}"#,
            r#"{"field":"Path","operator":"ends_with","pattern":".ts"}"#,
        ] {
            assert!(evaluate_condition(&v(cond), &payload), "{cond}");
        }
        assert_eq!(
            extract_field_from_payload(&payload, "tool_name"),
            "run_command"
        );
    }

    #[test]
    fn pre_tool_use_precedence_and_overwrite() {
        let rules = [
            v(
                r#"{"name":"rewrite-npm-to-pnpm","enabled":true,"event":"bash","action":"overwrite","conditions":[{"field":"CommandLine","operator":"starts_with","pattern":"npm test"}],"overwrite":{"field":"CommandLine","find":"^npm test","replace":"bazel test //..."},"message":"Rewrote npm test to bazel test //..."}"#,
            ),
            v(
                r#"{"name":"ask-on-test","enabled":true,"event":"bash","action":"warn","conditions":[{"field":"CommandLine","operator":"contains","pattern":"test"}],"message":"Confirm test run."}"#,
            ),
        ];
        let payload =
            v(r#"{"toolCall":{"name":"run_command","args":{"CommandLine":"npm test --watch"}}}"#);
        let res = evaluate_pre_tool_use(&rules, &payload);
        assert_eq!(res.decision, "ask");
        assert_eq!(res.permission_decision, "ask");
        assert_eq!(res.matched_rules.len(), 2);
        assert_eq!(
            Value::Object(res.updated_input.unwrap()).to_string(),
            r#"{"CommandLine":"bazel test //... --watch"}"#
        );
        assert_eq!(
            v(&res.hook_output_json)["hookSpecificOutput"]["updatedInput"]["CommandLine"],
            "bazel test //... --watch"
        );
    }

    #[test]
    fn deny_wins_and_disabled_rules_are_ignored() {
        let rules = [
            v(
                r#"{"name":"disabled-block","enabled":false,"event":"bash","action":"block","pattern":".*","message":"Should not fire"}"#,
            ),
            v(
                r#"{"name":"deny-prod-drop","enabled":true,"event":"bash","action":"deny","pattern":"DROP\\s+TABLE","message":"Prod table drops are forbidden."}"#,
            ),
        ];
        let res = evaluate_pre_tool_use(
            &rules,
            &v(
                r#"{"toolCall":{"name":"run_command","args":{"CommandLine":"psql -c 'DROP TABLE users;'"}}}"#,
            ),
        );
        assert_eq!(res.decision, "deny");
        assert_eq!(res.matched_rules.len(), 1);
        assert!(res.reason.contains("Prod table drops are forbidden"));
    }

    #[test]
    fn stop_rule_blocks_and_allows() {
        let rules = [v(
            r#"{"name":"require-worktree-hygiene","enabled":true,"event":"Stop","action":"block","conditions":[{"field":"reason","operator":"not_contains","pattern":"worktree hygiene"}],"message":"Include worktree hygiene status before stopping."}"#,
        )];
        let blocked = evaluate_stop(
            &rules,
            &v(r#"{"hook_event_name":"Stop","reason":"All done!"}"#),
        );
        assert!(!blocked.continue_flag);
        assert_eq!(v(&blocked.hook_output_json)["continue"], false);
        assert!(blocked
            .stop_reason
            .contains("Include worktree hygiene status"));
        let allowed = evaluate_stop(
            &rules,
            &v(r#"{"hook_event_name":"Stop","reason":"All done! Verified worktree hygiene."}"#),
        );
        assert!(allowed.continue_flag);
        assert_eq!(allowed.hook_output_json, ALLOW);
    }

    // ---- Parity gaps the serde version had --------------------------------

    #[test]
    fn regex_rules_use_javascript_semantics() {
        // Lookahead and lazy quantifiers failed to compile, so the rule
        // never fired; group backtracking missed real matches.
        let payload = v(
            r#"{"toolCall":{"name":"run_command","args":{"CommandLine":"git push --force origin"}}}"#,
        );
        for (pattern, want) in [
            ("--force(?!-with-lease)", true),
            ("push.*?origin", true),
            ("(a|git )push", true),
            ("\\x67it", true),
        ] {
            let cond = obj([
                ("field", Value::from("CommandLine")),
                ("operator", Value::from("regex_match")),
                ("pattern", Value::from(pattern)),
            ]);
            assert_eq!(evaluate_condition(&cond, &payload), want, "{pattern}");
        }
        let lease = v(
            r#"{"toolCall":{"name":"run_command","args":{"CommandLine":"git push --force-with-lease"}}}"#,
        );
        let cond = v(r#"{"field":"CommandLine","pattern":"--force(?!-with-lease)"}"#);
        assert!(!evaluate_condition(&cond, &lease));
    }

    #[test]
    fn output_keeps_argument_order_and_javascript_numbers() {
        // serde_json sorted keys and printed 1e2 as 100.0.
        let rules = [v(
            r#"{"name":"o","event":"bash","action":"overwrite","pattern":"x","overwrite":{"Alpha":1e2}}"#,
        )];
        let payload =
            v(r#"{"toolCall":{"name":"run_command","args":{"Zulu":"z","CommandLine":"x"}}}"#);
        let res = evaluate_pre_tool_use(&rules, &payload);
        assert_eq!(
            v(&res.hook_output_json)["updatedInput"].to_string(),
            r#"{"Zulu":"z","CommandLine":"x","Alpha":100}"#
        );
    }

    #[test]
    fn markdown_reads_scalars_and_fences_like_the_script() {
        // "+5" and ".5" are strings in JavaScript's /^-?\d+(\.\d+)?$/.
        let rule = parse_hookify_markdown("---\nid: +5\nname: .5\n---\n", "").unwrap();
        assert_eq!(rule["id"], "+5");
        assert_eq!(rule["name"], ".5");
        // An empty frontmatter has no "\n---" to end it: not a rule.
        assert!(parse_hookify_markdown("---\n---\n", "").is_none());
        // The frontmatter ends at the first "\n---", even "\n----".
        let rule = parse_hookify_markdown("---\nname: a\n----\nbody", "").unwrap();
        assert_eq!(rule["message"], "-\nbody");
        // A dotted top-level key is not a key.
        let rule = parse_hookify_markdown("---\nname.x: a\n---\n", "x/hookify.n.md").unwrap();
        assert_eq!(rule["name"], "n");
        // No ".md" suffix: the file name itself, not "unnamed-rule".
        let rule = parse_hookify_markdown("---\nx: 1\n---\n", "a/hookify.rule.txt").unwrap();
        assert_eq!(rule["name"], "rule.txt");
        // `pattern: null` still makes a condition, with pattern "null".
        let rule = parse_hookify_markdown("---\npattern: null\n---\n", "").unwrap();
        assert_eq!(rule["conditions"][0]["pattern"], "null");
        // `name: 0` is falsy, so the fallback name applies.
        let rule = parse_hookify_markdown("---\nname: 0\n---\n", "").unwrap();
        assert_eq!(rule["name"], "unnamed-rule");
    }

    #[test]
    fn tool_name_prefers_tool_call_name() {
        // The serde version read `tool_name` (or an argument of that name)
        // first.
        let rule = v(r#"{"name":"r","tool":"run_command","pattern":"x"}"#);
        let payload = v(
            r#"{"tool_name":"other","toolCall":{"name":"run_command","args":{"CommandLine":"x","tool_name":"nope"}}}"#,
        );
        assert!(evaluate_rule(&rule, &payload, "PreToolUse").matched);
    }

    #[test]
    fn overwrite_with_null_replace_and_dollar_patterns() {
        // `replace: null` is defined, so the find/replace path runs ("null").
        let rule = v(r#"{"overwrite":{"field":"CommandLine","find":"x","replace":null}}"#);
        let args = v(r#"{"CommandLine":"axb"}"#).as_object().unwrap().clone();
        let out = compute_overwritten_input(rule.as_object().unwrap(), &args);
        assert_eq!(out["CommandLine"], "anullb");
        // `$1` and `$&` expand, as in String.prototype.replace.
        let rule = v(
            r#"{"overwrite":{"field":"CommandLine","find":"npm (\\w+)","replace":"pnpm $1 [$&]"}}"#,
        );
        let args = v(r#"{"CommandLine":"npm test"}"#)
            .as_object()
            .unwrap()
            .clone();
        let out = compute_overwritten_input(rule.as_object().unwrap(), &args);
        assert_eq!(out["CommandLine"], "pnpm test [npm test]");
    }

    #[test]
    fn field_values_are_coerced_like_string() {
        let payload = v(
            r#"{"toolCall":{"name":"t","args":{"Obj":{"a":1},"Arr":[1,null,"x"]}},"Top":{"b":2}}"#,
        );
        assert_eq!(
            extract_field_from_payload(&payload, "Obj"),
            "[object Object]"
        );
        assert_eq!(extract_field_from_payload(&payload, "Arr"), "1,,x");
        assert_eq!(extract_field_from_payload(&payload, "Top"), r#"{"b":2}"#);
        // A blank operator is "" after trim: no operator, no match.
        let cond = v(r#"{"field":"Obj","operator":"  ","pattern":"x"}"#);
        assert!(!evaluate_condition(&cond, &payload));
    }

    #[test]
    fn audit_log_keeps_unknown_fields_and_skips_unparseable_files() {
        let app = temp_dir("audit");
        let ws = temp_dir("audit-ws");
        fs::write(
            app.join("hookify-rules.json"),
            r#"{"rules":[{"name":"deny-rm","event":"bash","action":"deny","pattern":"rm -rf"}]}"#,
        )
        .unwrap();
        // An older entry with a field this version does not know about.
        fs::write(
            app.join("hookify-events.json"),
            r#"[{"id":"old","extra":true}]"#,
        )
        .unwrap();
        let payload = format!(
            r#"{{"toolCall":{{"name":"run_command","args":{{"CommandLine":"rm -rf /","Cwd":"{}"}}}}}}"#,
            ws.display()
        );
        let out = handle_hookify_payload(&payload, Some(&app));
        assert_eq!(v(&out)["permissionDecision"], "deny");
        let events = v(&fs::read_to_string(app.join("hookify-events.json")).unwrap());
        assert_eq!(events[0]["decision"], "deny");
        assert_eq!(events[0]["tool"], "run_command");
        assert_eq!(events[1].to_string(), r#"{"id":"old","extra":true}"#);
        let id = events[0]["id"].as_str().unwrap();
        assert!(id
            .split_once('-')
            .is_some_and(|(_, r)| r.len() == 5 && r != "rust0"));

        // A file that is not JSON is left alone.
        fs::write(app.join("hookify-events.json"), "not json").unwrap();
        handle_hookify_payload(&payload, Some(&app));
        assert_eq!(
            fs::read_to_string(app.join("hookify-events.json")).unwrap(),
            "not json"
        );
    }

    #[test]
    fn workspace_rules_load_in_order_from_cwd() {
        let app = temp_dir("ws-app");
        let ws = temp_dir("ws");
        fs::create_dir_all(ws.join(".agents")).unwrap();
        fs::write(
            ws.join(".agents/hookify.b.md"),
            "---\nname: b\nevent: bash\naction: deny\npattern: danger\n---\nB says no.",
        )
        .unwrap();
        fs::write(
            ws.join(".agents/hookify.a.md"),
            "---\nname: a\nevent: bash\naction: warn\npattern: danger\n---\nA warns.",
        )
        .unwrap();
        fs::write(
            ws.join(".agents/hookify..md"),
            "---\nname: skip\npattern: danger\n---\n",
        )
        .unwrap();
        let payload = r#"{"toolCall":{"name":"run_command","args":{"CommandLine":"danger"}}}"#;
        let out = handle_at(payload, Some(&app), Some(ws.clone()));
        assert_eq!(
            v(&out)["permissionDecisionReason"],
            "[a] A warns.\n\n[b] B says no."
        );
    }

    #[test]
    fn no_answer_is_ever_empty() {
        // Antigravity denies a tool call whose PreToolUse hook prints `{}`.
        let app = temp_dir("never-empty");
        let none = temp_dir("never-empty-ws");
        fs::write(
            app.join("hookify-rules.json"),
            r#"[{"name":"w","event":"bash","action":"warn","pattern":"warnme"},{"name":"o","event":"bash","action":"overwrite","pattern":"npm","overwrite":{"field":"CommandLine","find":"npm","replace":"pnpm"}},{"name":"s","event":"stop","action":"warn","pattern":"done"}]"#,
        )
        .unwrap();
        for payload in [
            "",
            "   ",
            "not json",
            "5",
            "null",
            "[]",
            "{}",
            r#"{"toolCall":{"name":"run_command","args":{"CommandLine":"ls"}}}"#,
            r#"{"toolCall":{"name":"run_command","args":{"CommandLine":"warnme"}}}"#,
            r#"{"toolCall":{"name":"run_command","args":{"CommandLine":"npm i"}}}"#,
            r#"{"toolCall":{"name":"run_command","args":{"Cwd":5}}}"#,
            r#"{"hook_event_name":"Stop","reason":"all done"}"#,
            r#"{"hook_event_name":"Stop","reason":"nothing"}"#,
            r#"{"executionNum":1,"terminationReason":"NO_TOOL_CALL"}"#,
        ] {
            let out = handle_at(payload, Some(&app), Some(none.clone()));
            let parsed = v(&out);
            assert!(
                parsed["decision"].as_str().is_some_and(|d| !d.is_empty()),
                "{payload:?} gave {out}"
            );
        }
        // The rewrite reaches Antigravity as `overwrite`.
        let out = handle_at(
            r#"{"toolCall":{"name":"run_command","args":{"CommandLine":"npm i","Cwd":"/w"}}}"#,
            Some(&app),
            Some(none.clone()),
        );
        assert!(
            out.starts_with(r#"{"decision":"allow","reason":"[o] Rule 'o' matched.","overwrite":{"CommandLine":"pnpm i","Cwd":"/w"},"#),
            "{out}"
        );
        let out = handle_at(
            r#"{"toolCall":{"name":"run_command","args":{"CommandLine":"warnme"}}}"#,
            Some(&app),
            Some(none),
        );
        assert_eq!(v(&out)["decision"], "ask");
    }

    #[test]
    fn file_rules_read_antigravity_file_tools() {
        let rule = v(
            r#"{"name":"no-secrets","event":"file","action":"deny","conditions":[{"field":"file_path","operator":"ends_with","pattern":".env"},{"field":"content","operator":"contains","pattern":"API_KEY"}]}"#,
        );
        let target = v(
            r#"{"name":"no-target","event":"file","action":"deny","conditions":[{"field":"Target","operator":"contains","pattern":"OLD"}]}"#,
        );
        for (payload, rule, want) in [
            (
                r#"{"toolCall":{"name":"write_file","args":{"Path":"a.env","Content":"API_KEY=1"}}}"#,
                &rule,
                true,
            ),
            (
                r#"{"toolCall":{"name":"edit_file","args":{"Path":"a.env","Target":"x","Replacement":"API_KEY=1"}}}"#,
                &rule,
                true,
            ),
            (
                r#"{"toolCall":{"name":"write_to_file","args":{"TargetFile":"/w/a.env","CodeContent":"API_KEY=1"}}}"#,
                &rule,
                true,
            ),
            (
                r#"{"toolCall":{"name":"replace_file_content","args":{"TargetFile":"/w/a.env","TargetContent":"x","ReplacementContent":"API_KEY=1"}}}"#,
                &rule,
                true,
            ),
            (
                r#"{"toolCall":{"name":"multi_replace_file_content","args":{"TargetFile":"/w/a.env","ReplacementChunks":[{"TargetContent":"a","ReplacementContent":"ok"},{"TargetContent":"b","ReplacementContent":"API_KEY=2"}]}}}"#,
                &rule,
                true,
            ),
            (
                r#"{"toolCall":{"name":"write_to_file","args":{"AbsolutePath":"/w/a.env","CodeContent":"API_KEY=1"}}}"#,
                &rule,
                true,
            ),
            (
                r#"{"toolCall":{"name":"write_to_file","args":{"TargetFile":"/w/a.txt","CodeContent":"API_KEY=1"}}}"#,
                &rule,
                false,
            ),
            (
                r#"{"toolCall":{"name":"replace_file_content","args":{"TargetFile":"f","TargetContent":"OLD","ReplacementContent":"n"}}}"#,
                &target,
                true,
            ),
            (
                r#"{"toolCall":{"name":"multi_replace_file_content","args":{"TargetFile":"f","ReplacementChunks":[{"TargetContent":"OLD","ReplacementContent":"n"}]}}}"#,
                &target,
                true,
            ),
            (
                r#"{"toolCall":{"name":"run_command","args":{"CommandLine":"echo API_KEY > a.env"}}}"#,
                &rule,
                false,
            ),
        ] {
            let got = evaluate_rule(rule, &v(payload), "PreToolUse").matched;
            assert_eq!(got, want, "{payload}");
        }
    }

    #[test]
    fn stop_detection_and_bad_payloads() {
        let app = temp_dir("stop");
        fs::write(
            app.join("hookify-rules.json"),
            r#"[{"name":"s","event":"stop","action":"block","pattern":"later"}]"#,
        )
        .unwrap();
        let none = temp_dir("stop-none");
        let run = |p: &str| handle_at(p, Some(&app), Some(none.clone()));
        // `toolCall: null` is absent, so `reason` makes it a Stop event.
        let out = run(r#"{"toolCall":null,"reason":"do it later"}"#);
        assert_eq!(v(&out)["decision"], "block");
        assert_eq!(run(""), ALLOW);
        assert_eq!(run("nope"), ALLOW);
        assert_eq!(run("5"), ALLOW);
        assert_eq!(run("null"), ALLOW);
        // A non-string Cwd made path.join throw.
        assert_eq!(run(r#"{"toolCall":{"name":"x","args":{"Cwd":5}}}"#), ALLOW);
    }
}
