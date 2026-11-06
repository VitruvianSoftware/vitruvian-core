// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

use serde_json::{json, Map, Number, Value};
use std::collections::{BTreeMap, HashSet};

pub const OPENUI_LANG_VERSION: &str = "0.5";

#[derive(Debug, Clone, PartialEq)]
pub struct ParsedOpenUI {
    pub root: Value,
    pub bindings: BTreeMap<String, Value>,
    pub order: Vec<String>,
}

#[derive(Debug, Clone, Default)]
pub struct RenderOpts {
    pub title: Option<String>,
    pub footer: Option<String>,
    pub data: Option<Value>,
}

pub fn escape_html(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for ch in value.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            _ => out.push(ch),
        }
    }
    out
}

pub fn escape_html_opt(value: Option<&Value>) -> String {
    match value {
        None | Some(Value::Null) => String::new(),
        Some(Value::String(s)) => escape_html(s),
        Some(Value::Bool(b)) => escape_html(if *b { "true" } else { "false" }),
        Some(Value::Number(n)) => escape_html(&n.to_string()),
        Some(other) => escape_html(&other.to_string()),
    }
}

fn val_to_str(value: Option<&Value>) -> String {
    match value {
        None | Some(Value::Null) => String::new(),
        Some(Value::String(s)) => s.clone(),
        Some(Value::Bool(b)) => (if *b { "true" } else { "false" }).to_string(),
        Some(Value::Number(n)) => n.to_string(),
        Some(other) => other.to_string(),
    }
}

fn is_truthy(value: Option<&Value>) -> bool {
    match value {
        None | Some(Value::Null) | Some(Value::Bool(false)) => false,
        Some(Value::String(s)) => !s.is_empty(),
        Some(Value::Number(n)) => n.as_f64().map(|f| f != 0.0 && !f.is_nan()).unwrap_or(false),
        Some(Value::Bool(true)) | Some(Value::Array(_)) | Some(Value::Object(_)) => true,
    }
}

pub fn resolve_data_path(context: &Value, path_str: &str) -> Option<Value> {
    if path_str.is_empty() || context.is_null() {
        return None;
    }
    let clean = path_str.strip_prefix('$').unwrap_or(path_str);
    let parts: Vec<&str> = clean.split('.').collect();
    let mut current = context;
    for (i, part) in parts.iter().enumerate() {
        if current.is_null() {
            return None;
        }
        if let Value::Array(arr) = current {
            let rest = parts[i..].join(".");
            let mapped: Vec<Value> = arr
                .iter()
                .map(|item| resolve_data_path(item, &rest).unwrap_or(Value::Null))
                .collect();
            return Some(Value::Array(mapped));
        }
        if let Value::Object(map) = current {
            if let Some(next) = map.get(*part) {
                current = next;
            } else {
                return None;
            }
        } else {
            return None;
        }
    }
    Some(current.clone())
}

#[derive(Debug, Clone, PartialEq)]
enum Token {
    Punct(char),
    String(String),
    Number(Number),
    Bool(bool),
    Null,
    Ident(String),
}

fn tokenize(input: &str) -> Vec<Token> {
    let mut tokens = Vec::new();
    let chars: Vec<char> = input.chars().collect();
    let len = chars.len();
    let mut i = 0;

    while i < len {
        let ch = chars[i];
        if ch.is_whitespace() {
            i += 1;
            continue;
        }
        if ch == '#' || (ch == '/' && i + 1 < len && chars[i + 1] == '/') {
            while i < len && chars[i] != '\n' {
                i += 1;
            }
            continue;
        }
        if "()[],=+:".contains(ch) {
            tokens.push(Token::Punct(ch));
            i += 1;
            continue;
        }
        if ch == '"' || ch == '\'' {
            let quote = ch;
            i += 1;
            let mut str_val = String::new();
            while i < len && chars[i] != quote {
                if chars[i] == '\\' && i + 1 < len {
                    let next = chars[i + 1];
                    match next {
                        'n' => str_val.push('\n'),
                        't' => str_val.push('\t'),
                        'r' => str_val.push('\r'),
                        '"' => str_val.push('"'),
                        '\'' => str_val.push('\''),
                        '\\' => str_val.push('\\'),
                        other => str_val.push(other),
                    }
                    i += 2;
                } else {
                    str_val.push(chars[i]);
                    i += 1;
                }
            }
            i += 1;
            tokens.push(Token::String(str_val));
            continue;
        }
        if ch.is_ascii_digit() || (ch == '-' && i + 1 < len && chars[i + 1].is_ascii_digit()) {
            let mut num_str = String::new();
            num_str.push(ch);
            i += 1;
            let mut has_dot = false;
            while i < len && (chars[i].is_ascii_digit() || chars[i] == '.') {
                if chars[i] == '.' {
                    has_dot = true;
                }
                num_str.push(chars[i]);
                i += 1;
            }
            let num = if !has_dot {
                if let Ok(int_val) = num_str.parse::<i64>() {
                    Number::from(int_val)
                } else if let Ok(f_val) = num_str.parse::<f64>() {
                    Number::from_f64(f_val).unwrap_or_else(|| Number::from(0))
                } else {
                    Number::from(0)
                }
            } else if let Ok(f_val) = num_str.parse::<f64>() {
                Number::from_f64(f_val).unwrap_or_else(|| Number::from(0))
            } else {
                Number::from(0)
            };
            tokens.push(Token::Number(num));
            continue;
        }
        if ch.is_ascii_alphabetic() || ch == '_' || ch == '$' {
            let mut ident = String::new();
            ident.push(ch);
            i += 1;
            while i < len
                && (chars[i].is_ascii_alphanumeric()
                    || chars[i] == '_'
                    || chars[i] == '$'
                    || chars[i] == '.'
                    || chars[i] == '-')
            {
                ident.push(chars[i]);
                i += 1;
            }
            match ident.as_str() {
                "true" => tokens.push(Token::Bool(true)),
                "false" => tokens.push(Token::Bool(false)),
                "null" => tokens.push(Token::Null),
                _ => tokens.push(Token::Ident(ident)),
            }
            continue;
        }
        i += 1;
    }

    tokens
}

fn parse_expr(tokens: &[Token], pos: &mut usize) -> Value {
    let mut left = parse_primary(tokens, pos);
    while *pos < tokens.len() && tokens[*pos] == Token::Punct('+') {
        *pos += 1;
        let right = parse_primary(tokens, pos);
        left = json!({
            "$op": "+",
            "left": left,
            "right": right,
        });
    }
    left
}

fn parse_primary(tokens: &[Token], pos: &mut usize) -> Value {
    if *pos >= tokens.len() {
        return Value::Null;
    }
    match &tokens[*pos] {
        Token::String(s) => {
            let v = Value::String(s.clone());
            *pos += 1;
            v
        }
        Token::Number(n) => {
            let v = Value::Number(n.clone());
            *pos += 1;
            v
        }
        Token::Bool(b) => {
            let v = Value::Bool(*b);
            *pos += 1;
            v
        }
        Token::Null => {
            *pos += 1;
            Value::Null
        }
        Token::Punct('[') => {
            *pos += 1;
            let mut items = Vec::new();
            while *pos < tokens.len() && tokens[*pos] != Token::Punct(']') {
                if tokens[*pos] == Token::Punct(',') {
                    *pos += 1;
                    continue;
                }
                items.push(parse_expr(tokens, pos));
                if *pos < tokens.len() && tokens[*pos] == Token::Punct(',') {
                    *pos += 1;
                }
            }
            if *pos < tokens.len() && tokens[*pos] == Token::Punct(']') {
                *pos += 1;
            }
            Value::Array(items)
        }
        Token::Ident(name) => {
            let ident_name = name.clone();
            *pos += 1;
            if *pos < tokens.len() && tokens[*pos] == Token::Punct('(') {
                *pos += 1;
                let mut args = Vec::new();
                while *pos < tokens.len() && tokens[*pos] != Token::Punct(')') {
                    if tokens[*pos] == Token::Punct(',') {
                        *pos += 1;
                        continue;
                    }
                    args.push(parse_expr(tokens, pos));
                    if *pos < tokens.len() && tokens[*pos] == Token::Punct(',') {
                        *pos += 1;
                    }
                }
                if *pos < tokens.len() && tokens[*pos] == Token::Punct(')') {
                    *pos += 1;
                }
                json!({
                    "$component": ident_name,
                    "args": args,
                })
            } else {
                json!({ "$ref": ident_name })
            }
        }
        _ => {
            *pos += 1;
            Value::Null
        }
    }
}

fn resolve_node(
    node: &Value,
    bindings: &BTreeMap<String, Value>,
    ctx: &Value,
    seen: &HashSet<String>,
) -> Value {
    match node {
        Value::Null | Value::Bool(_) | Value::Number(_) | Value::String(_) => node.clone(),
        Value::Array(arr) => Value::Array(
            arr.iter()
                .map(|item| resolve_node(item, bindings, ctx, seen))
                .collect(),
        ),
        Value::Object(map) => {
            if let Some(Value::String(ref_name)) = map.get("$ref") {
                if seen.contains(ref_name) {
                    return Value::Null;
                }
                if let Some(target) = bindings.get(ref_name) {
                    let mut next_seen = seen.clone();
                    next_seen.insert(ref_name.clone());
                    return resolve_node(target, bindings, ctx, &next_seen);
                }
                if ref_name.contains('.') || ref_name.starts_with('$') {
                    return resolve_data_path(ctx, ref_name).unwrap_or(Value::Null);
                }
                if let Value::Object(ctx_map) = ctx {
                    if let Some(val) = ctx_map.get(ref_name) {
                        return val.clone();
                    }
                }
                return Value::String(ref_name.clone());
            }
            if map.get("$op").and_then(|v| v.as_str()) == Some("+") {
                let l = resolve_node(map.get("left").unwrap_or(&Value::Null), bindings, ctx, seen);
                let r = resolve_node(
                    map.get("right").unwrap_or(&Value::Null),
                    bindings,
                    ctx,
                    seen,
                );
                return Value::String(format!("{}{}", val_to_str(Some(&l)), val_to_str(Some(&r))));
            }
            if let Some(Value::String(comp)) = map.get("$component") {
                let args = map
                    .get("args")
                    .and_then(|v| v.as_array())
                    .map(|arr| {
                        arr.iter()
                            .map(|a| resolve_node(a, bindings, ctx, seen))
                            .collect::<Vec<_>>()
                    })
                    .unwrap_or_default();
                return json!({
                    "$component": comp,
                    "args": args,
                });
            }
            node.clone()
        }
    }
}

pub fn parse_openui_lang(source: &str, data: Option<&Value>) -> ParsedOpenUI {
    let mut bindings = BTreeMap::new();
    let mut order = Vec::new();
    if source.is_empty() {
        return ParsedOpenUI {
            root: Value::Null,
            bindings,
            order,
        };
    }

    let tokens = tokenize(source);
    let mut pos = 0;

    while pos < tokens.len() {
        if let Token::Ident(name) = &tokens[pos] {
            if pos + 1 < tokens.len() && tokens[pos + 1] == Token::Punct('=') {
                let name_owned = name.clone();
                pos += 2;
                let expr = parse_expr(&tokens, &mut pos);
                if !bindings.contains_key(&name_owned) {
                    order.push(name_owned.clone());
                }
                bindings.insert(name_owned, expr);
                continue;
            }
        }
        let expr = parse_expr(&tokens, &mut pos);
        if !bindings.contains_key("root") {
            bindings.insert("root".to_string(), expr);
            order.push("root".to_string());
        }
    }

    let mut ctx_map = Map::new();
    let data_val = data.cloned().unwrap_or_else(|| json!({}));
    if let Value::Object(m) = &data_val {
        for (k, v) in m {
            ctx_map.insert(k.clone(), v.clone());
        }
    }
    ctx_map.insert("data".to_string(), data_val);
    let ctx = Value::Object(ctx_map);

    let root = bindings
        .get("root")
        .map(|r| resolve_node(r, &bindings, &ctx, &HashSet::new()))
        .unwrap_or(Value::Null);

    ParsedOpenUI {
        root,
        bindings,
        order,
    }
}

pub fn render_node_to_html(node: &Value, opts: &RenderOpts) -> String {
    match node {
        Value::Null => String::new(),
        Value::String(s) => escape_html(s),
        Value::Number(n) => escape_html(&n.to_string()),
        Value::Bool(b) => escape_html(if *b { "true" } else { "false" }),
        Value::Array(arr) => arr
            .iter()
            .map(|n| render_node_to_html(n, opts))
            .collect::<Vec<_>>()
            .join(""),
        Value::Object(map) => {
            let Some(Value::String(comp)) = map.get("$component") else {
                return String::new();
            };
            let args: &[Value] = map
                .get("args")
                .and_then(|v| v.as_array())
                .map(|v| v.as_slice())
                .unwrap_or(&[]);

            match comp.as_str() {
                "Card" => {
                    let children = args.first().unwrap_or(&Value::Null);
                    format!(
                        "<div class=\"openui-card\" data-openui-component=\"Card\">{}</div>",
                        render_node_to_html(children, opts)
                    )
                }
                "Header" => {
                    let title = args.first();
                    let subtitle = args.get(1);
                    let badge_text = args.get(2);
                    let badge_tone = args
                        .get(3)
                        .filter(|v| is_truthy(Some(v)))
                        .map(|v| val_to_str(Some(v)))
                        .unwrap_or_else(|| "neutral".to_string());
                    let sub_html = if is_truthy(subtitle) {
                        format!(
                            "<span class=\"openui-subtitle\">{}</span>",
                            escape_html_opt(subtitle)
                        )
                    } else {
                        String::new()
                    };
                    let badge_html = if is_truthy(badge_text) {
                        format!(
                            "<span class=\"openui-badge tone-{}\">{}</span>",
                            escape_html(&badge_tone),
                            escape_html_opt(badge_text)
                        )
                    } else {
                        String::new()
                    };
                    format!(
                        "<div class=\"openui-header\" data-openui-component=\"Header\"><div class=\"openui-header-titles\"><h1 class=\"openui-title\">{}</h1>{}</div>{}</div>",
                        escape_html_opt(title),
                        sub_html,
                        badge_html
                    )
                }
                "Grid" => {
                    let cols = args
                        .first()
                        .and_then(|v| v.as_i64())
                        .unwrap_or(4)
                        .clamp(1, 6);
                    let children = args.get(1).unwrap_or(&Value::Null);
                    format!(
                        "<div class=\"openui-grid cols-{}\" data-openui-component=\"Grid\">{}</div>",
                        cols,
                        render_node_to_html(children, opts)
                    )
                }
                "Kpi" => {
                    let label = args.first();
                    let value = args.get(1);
                    let sub = args.get(2);
                    let tone = args
                        .get(3)
                        .filter(|v| is_truthy(Some(v)))
                        .map(|v| val_to_str(Some(v)))
                        .unwrap_or_else(|| "neutral".to_string());
                    let sub_html = if is_truthy(sub) {
                        format!(
                            "<div class=\"openui-kpi-sub\">{}</div>",
                            escape_html_opt(sub)
                        )
                    } else {
                        String::new()
                    };
                    format!(
                        "<div class=\"openui-kpi tone-{}\" data-openui-component=\"Kpi\"><div class=\"openui-kpi-label\">{}</div><div class=\"openui-kpi-value\">{}</div>{}</div>",
                        escape_html(&tone),
                        escape_html_opt(label),
                        escape_html_opt(value),
                        sub_html
                    )
                }
                "Table" => {
                    let cols_raw: Vec<&Value> = match args.first() {
                        Some(Value::Array(arr)) => arr.iter().collect(),
                        Some(other) => vec![other],
                        None => vec![],
                    };
                    let empty_text = args
                        .get(1)
                        .filter(|v| is_truthy(Some(v)))
                        .map(|v| val_to_str(Some(v)))
                        .unwrap_or_else(|| "No rows.".to_string());
                    struct ColDef {
                        header: String,
                        values: Vec<Value>,
                        kind: String,
                    }
                    let cols: Vec<ColDef> = cols_raw
                        .into_iter()
                        .filter(|c| c.get("$component").and_then(|v| v.as_str()) == Some("Col"))
                        .map(|c| {
                            let c_args = c
                                .get("args")
                                .and_then(|v| v.as_array())
                                .map(|v| v.as_slice())
                                .unwrap_or(&[]);
                            let header = val_to_str(c_args.first());
                            let values = match c_args.get(1) {
                                Some(Value::Array(arr)) => arr.clone(),
                                Some(other) => vec![other.clone()],
                                None => vec![],
                            };
                            let kind = c_args
                                .get(2)
                                .filter(|v| is_truthy(Some(v)))
                                .map(|v| val_to_str(Some(v)))
                                .unwrap_or_else(|| "text".to_string());
                            ColDef {
                                header,
                                values,
                                kind,
                            }
                        })
                        .collect();
                    let row_count = cols.iter().map(|c| c.values.len()).max().unwrap_or(0);
                    let headers = cols
                        .iter()
                        .map(|c| format!("<th>{}</th>", escape_html(&c.header)))
                        .collect::<Vec<_>>()
                        .join("");
                    let mut rows_html = String::new();
                    if row_count == 0 {
                        rows_html = format!(
                            "<tr><td colspan=\"{}\" class=\"openui-empty\">{}</td></tr>",
                            cols.len().max(1),
                            escape_html(&empty_text)
                        );
                    } else {
                        for r in 0..row_count {
                            let cells = cols
                                .iter()
                                .map(|c| {
                                    let val = c.values.get(r).unwrap_or(&Value::Null);
                                    if val.get("$component").is_some() {
                                        return format!(
                                            "<td>{}</td>",
                                            render_node_to_html(val, opts)
                                        );
                                    }
                                    if c.kind == "code" || c.kind == "mono" {
                                        return format!(
                                            "<td class=\"cell-mono\">{}</td>",
                                            escape_html_opt(Some(val))
                                        );
                                    }
                                    if c.kind == "number" {
                                        return format!(
                                            "<td class=\"cell-num\">{}</td>",
                                            escape_html_opt(Some(val))
                                        );
                                    }
                                    format!("<td>{}</td>", escape_html_opt(Some(val)))
                                })
                                .collect::<Vec<_>>()
                                .join("");
                            rows_html.push_str(&format!("<tr>{cells}</tr>"));
                        }
                    }
                    format!(
                        "<div class=\"openui-table-wrap\" data-openui-component=\"Table\"><table class=\"openui-table\"><thead><tr>{}</tr></thead><tbody>{}</tbody></table></div>",
                        headers, rows_html
                    )
                }
                _ => {
                    let inner = args
                        .iter()
                        .map(|a| render_node_to_html(a, opts))
                        .collect::<Vec<_>>()
                        .join("");
                    format!(
                        "<div class=\"openui-unknown\" data-openui-component=\"{}\">{}</div>",
                        escape_html(comp),
                        inner
                    )
                }
            }
        }
    }
}

pub fn render_openui_fragment(dsl_source: &str, opts: &RenderOpts) -> String {
    let parsed = parse_openui_lang(dsl_source, opts.data.as_ref());
    if parsed.root.is_null() {
        return "<div class=\"openui-empty\">Empty OpenUI document.</div>".to_string();
    }
    render_node_to_html(&parsed.root, opts)
}

pub fn compile_to_html(dsl_source: &str, opts: &RenderOpts) -> String {
    let title = opts.title.as_deref().unwrap_or("Antigravity Sidecar");
    let footer = opts.footer.as_deref().unwrap_or("");
    let fragment = render_openui_fragment(dsl_source, opts);
    let footer_html = if !footer.is_empty() {
        format!(
            "\n  <footer class=\"openui-footer\">{}</footer>",
            escape_html(footer)
        )
    } else {
        String::new()
    };
    format!(
        "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\" />\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />\n<title>{}</title>\n</head>\n<body>\n  <main class=\"openui-shell\">\n    {}{}\n  </main>\n</body>\n</html>",
        escape_html(title),
        fragment,
        footer_html
    )
}

pub fn openui_str(value: &str) -> String {
    let escaped = value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace("\r\n", "\\n")
        .replace('\r', "\\n")
        .replace('\n', "\\n")
        .replace('\t', "\\t");
    format!("\"{escaped}\"")
}

pub fn call(name: &str, args: &[String]) -> String {
    format!("{}({})", name, args.join(", "))
}

pub fn list(items: &[String]) -> String {
    format!("[{}]", items.join(", "))
}

pub fn to_openui_lang(state: &Value) -> String {
    let projects = state
        .get("projects")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let totals = state.get("totals").cloned().unwrap_or_else(|| json!({}));

    let session_count = totals
        .get("sessionCount")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let total_turns = totals
        .get("totalTurns")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let total_tool_calls = totals
        .get("totalToolCalls")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let estimated_tokens = totals
        .get("estimatedTokens")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let files_touched = totals
        .get("filesTouchedCount")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);

    let names: Vec<String> = projects
        .iter()
        .map(|p| openui_str(p.get("project").and_then(|v| v.as_str()).unwrap_or("")))
        .collect();
    let sessions: Vec<String> = projects
        .iter()
        .map(|p| {
            p.get("sessionCount")
                .and_then(|v| v.as_i64())
                .unwrap_or(0)
                .to_string()
        })
        .collect();
    let turns: Vec<String> = projects
        .iter()
        .map(|p| {
            p.get("totalTurns")
                .and_then(|v| v.as_i64())
                .unwrap_or(0)
                .to_string()
        })
        .collect();
    let tools: Vec<String> = projects
        .iter()
        .map(|p| {
            p.get("totalToolCalls")
                .and_then(|v| v.as_i64())
                .unwrap_or(0)
                .to_string()
        })
        .collect();
    let tokens: Vec<String> = projects
        .iter()
        .map(|p| {
            p.get("estimatedTokens")
                .and_then(|v| v.as_i64())
                .unwrap_or(0)
                .to_string()
        })
        .collect();
    let files: Vec<String> = projects
        .iter()
        .map(|p| {
            p.get("filesTouchedCount")
                .and_then(|v| v.as_i64())
                .unwrap_or(0)
                .to_string()
        })
        .collect();

    let header = call(
        "Header",
        &[
            openui_str("Receipts Report"),
            openui_str("Local Session Analytics"),
            openui_str(&format!("{session_count} sessions")),
            openui_str(if session_count > 0 { "info" } else { "neutral" }),
        ],
    );

    let kpis = call(
        "Grid",
        &[
            "4".to_string(),
            list(&[
                call(
                    "Kpi",
                    &[
                        openui_str("Sessions"),
                        session_count.to_string(),
                        openui_str(&format!("{} projects", projects.len())),
                        openui_str("info"),
                    ],
                ),
                call(
                    "Kpi",
                    &[
                        openui_str("Total Turns"),
                        total_turns.to_string(),
                        openui_str(&format!("{total_tool_calls} tool calls")),
                        openui_str("info"),
                    ],
                ),
                call(
                    "Kpi",
                    &[
                        openui_str("Estimated Tokens"),
                        estimated_tokens.to_string(),
                        openui_str("From local transcripts"),
                        openui_str("success"),
                    ],
                ),
                call(
                    "Kpi",
                    &[
                        openui_str("Files Touched"),
                        files_touched.to_string(),
                        openui_str("Unique files"),
                        openui_str("neutral"),
                    ],
                ),
            ]),
        ],
    );

    let table = call(
        "Table",
        &[
            list(&[
                call(
                    "Col",
                    &[openui_str("Project"), list(&names), openui_str("mono")],
                ),
                call(
                    "Col",
                    &[
                        openui_str("Sessions"),
                        list(&sessions),
                        openui_str("number"),
                    ],
                ),
                call(
                    "Col",
                    &[openui_str("Turns"), list(&turns), openui_str("number")],
                ),
                call(
                    "Col",
                    &[openui_str("Tool Calls"), list(&tools), openui_str("number")],
                ),
                call(
                    "Col",
                    &[
                        openui_str("Est. Tokens"),
                        list(&tokens),
                        openui_str("number"),
                    ],
                ),
                call(
                    "Col",
                    &[openui_str("Files"), list(&files), openui_str("number")],
                ),
            ]),
            openui_str("No session transcripts found yet."),
        ],
    );

    [
        "# receipts-report state as OpenUI Lang v0.5".to_string(),
        "root = Card([header, kpis, table])".to_string(),
        format!("header = {header}"),
        format!("kpis = {kpis}"),
        format!("table = {table}"),
        String::new(),
    ]
    .join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn to_openui_lang_serialises_receipts_state_and_compiles_to_html() {
        let state = json!({
            "projects": [
                {
                    "project": "vitruvian-core",
                    "sessionCount": 2,
                    "totalTurns": 10,
                    "totalToolCalls": 18,
                    "estimatedTokens": 12400,
                    "filesTouchedCount": 7
                }
            ],
            "totals": {
                "sessionCount": 2,
                "totalTurns": 10,
                "totalToolCalls": 18,
                "estimatedTokens": 12400,
                "filesTouchedCount": 7
            }
        });

        let dsl = to_openui_lang(&state);
        assert!(dsl.contains("root = Card([header, kpis, table])"));

        let parsed = parse_openui_lang(&dsl, None);
        assert_eq!(parsed.root["$component"], "Card");

        let html = compile_to_html(
            &dsl,
            &RenderOpts {
                title: Some("Receipts Report".to_string()),
                ..Default::default()
            },
        );
        assert!(html.contains("Receipts Report"));
        assert!(html.contains("vitruvian-core"));
        assert!(html.contains("12400"));
    }
}
