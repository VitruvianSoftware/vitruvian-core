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
            i += 1; // skip closing quote
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
                "Tabs" => {
                    let id = args
                        .first()
                        .filter(|v| is_truthy(Some(v)))
                        .map(|v| val_to_str(Some(v)))
                        .unwrap_or_else(|| "tabs".to_string());
                    let tabs_raw: Vec<&Value> = match args.get(1) {
                        Some(Value::Array(arr)) => arr.iter().collect(),
                        Some(other) => vec![other],
                        None => vec![],
                    };
                    let tabs: Vec<&Value> = tabs_raw
                        .into_iter()
                        .filter(|t| t.get("$component").and_then(|c| c.as_str()) == Some("Tab"))
                        .collect();
                    let buttons = tabs
                        .iter()
                        .enumerate()
                        .map(|(idx, t)| {
                            let t_args = t
                                .get("args")
                                .and_then(|v| v.as_array())
                                .map(|v| v.as_slice())
                                .unwrap_or(&[]);
                            let tab_id = t_args
                                .first()
                                .filter(|v| is_truthy(Some(v)))
                                .map(|v| val_to_str(Some(v)))
                                .unwrap_or_else(|| format!("tab-{idx}"));
                            let label = t_args
                                .get(1)
                                .filter(|v| is_truthy(Some(v)))
                                .map(|v| val_to_str(Some(v)))
                                .unwrap_or_else(|| tab_id.clone());
                            let active = if idx == 0 { " active" } else { "" };
                            format!(
                                "<button type=\"button\" class=\"openui-tab-btn{}\" data-tab-target=\"{}-{}\" onclick=\"switchOpenUITab('{}', '{}-{}')\">{}</button>",
                                active,
                                escape_html(&id),
                                escape_html(&tab_id),
                                escape_html(&id),
                                escape_html(&id),
                                escape_html(&tab_id),
                                escape_html(&label)
                            )
                        })
                        .collect::<Vec<_>>()
                        .join("");
                    let panels = tabs
                        .iter()
                        .enumerate()
                        .map(|(idx, t)| {
                            let t_args = t
                                .get("args")
                                .and_then(|v| v.as_array())
                                .map(|v| v.as_slice())
                                .unwrap_or(&[]);
                            let tab_id = t_args
                                .first()
                                .filter(|v| is_truthy(Some(v)))
                                .map(|v| val_to_str(Some(v)))
                                .unwrap_or_else(|| format!("tab-{idx}"));
                            let children = t_args.get(2).unwrap_or(&Value::Null);
                            let active = if idx == 0 { " active" } else { "" };
                            format!(
                                "<div class=\"openui-tab-panel{}\" id=\"{}-{}\" data-tab-group=\"{}\">{}</div>",
                                active,
                                escape_html(&id),
                                escape_html(&tab_id),
                                escape_html(&id),
                                render_node_to_html(children, opts)
                            )
                        })
                        .collect::<Vec<_>>()
                        .join("");
                    format!(
                        "<div class=\"openui-tabs\" data-openui-component=\"Tabs\" data-tabs-id=\"{}\"><div class=\"openui-tab-bar\" role=\"tablist\">{}</div>{}</div>",
                        escape_html(&id),
                        buttons,
                        panels
                    )
                }
                "Tab" => {
                    let children = args.get(2).unwrap_or(&Value::Null);
                    render_node_to_html(children, opts)
                }
                "Stack" => {
                    let children = args.first().unwrap_or(&Value::Null);
                    format!(
                        "<div class=\"openui-stack\" data-openui-component=\"Stack\">{}</div>",
                        render_node_to_html(children, opts)
                    )
                }
                "Split" => {
                    let left = args.first().unwrap_or(&Value::Null);
                    let right = args.get(1).unwrap_or(&Value::Null);
                    format!(
                        "<div class=\"openui-split\" data-openui-component=\"Split\"><div class=\"openui-split-col\">{}</div><div class=\"openui-split-col\">{}</div></div>",
                        render_node_to_html(left, opts),
                        render_node_to_html(right, opts)
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
                    let pct = args.get(4);
                    let bar_html = if let Some(Value::Number(n)) = pct {
                        if let Some(f) = n.as_f64() {
                            let clamped = f.round().clamp(0.0, 100.0) as i64;
                            format!(
                                "<div class=\"openui-kpi-bar\"><div class=\"openui-kpi-bar-fill fill-{}\" style=\"width: {}%\"></div></div>",
                                escape_html(&tone),
                                clamped
                            )
                        } else {
                            String::new()
                        }
                    } else {
                        String::new()
                    };
                    let sub_html = if is_truthy(sub) {
                        format!(
                            "<div class=\"openui-kpi-sub\">{}</div>",
                            escape_html_opt(sub)
                        )
                    } else {
                        String::new()
                    };
                    format!(
                        "<div class=\"openui-kpi tone-{}\" data-openui-component=\"Kpi\"><div class=\"openui-kpi-label\">{}</div><div class=\"openui-kpi-value\">{}</div>{}{}</div>",
                        escape_html(&tone),
                        escape_html_opt(label),
                        escape_html_opt(value),
                        sub_html,
                        bar_html
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
                "BarChart" => {
                    let labels: Vec<Value> = match args.first() {
                        Some(Value::Array(arr)) => arr.clone(),
                        _ => vec![],
                    };
                    let series_raw: Vec<&Value> = match args.get(1) {
                        Some(Value::Array(arr)) => arr.iter().collect(),
                        Some(other) => vec![other],
                        None => vec![],
                    };
                    let caption = args.get(2);
                    struct SeriesDef {
                        name: String,
                        values: Vec<f64>,
                        tone: String,
                    }
                    let series: Vec<SeriesDef> = series_raw
                        .into_iter()
                        .filter(|s| s.get("$component").and_then(|v| v.as_str()) == Some("Series"))
                        .map(|s| {
                            let s_args = s
                                .get("args")
                                .and_then(|v| v.as_array())
                                .map(|v| v.as_slice())
                                .unwrap_or(&[]);
                            let name = val_to_str(s_args.first());
                            let values = match s_args.get(1) {
                                Some(Value::Array(arr)) => {
                                    arr.iter().map(|v| v.as_f64().unwrap_or(0.0)).collect()
                                }
                                _ => vec![],
                            };
                            let tone = s_args
                                .get(2)
                                .filter(|v| is_truthy(Some(v)))
                                .map(|v| val_to_str(Some(v)))
                                .unwrap_or_else(|| "info".to_string());
                            SeriesDef { name, values, tone }
                        })
                        .collect();
                    let max_val = series
                        .iter()
                        .flat_map(|s| s.values.iter().copied())
                        .fold(1.0_f64, f64::max);
                    let rows = labels
                        .iter()
                        .enumerate()
                        .map(|(idx, lbl)| {
                            let bars = series
                                .iter()
                                .map(|s| {
                                    let val = s.values.get(idx).copied().unwrap_or(0.0);
                                    let pct = ((val / max_val) * 100.0).round().clamp(0.0, 100.0)
                                        as i64;
                                    let disp = if val.fract() == 0.0 {
                                        format!("{}", val as i64)
                                    } else {
                                        format!("{val}")
                                    };
                                    format!(
                                        "<div class=\"openui-bar-track\" title=\"{}: {}\"><div class=\"openui-bar-fill fill-{}\" style=\"width: {}%\"></div><span class=\"openui-bar-val\">{}</span></div>",
                                        escape_html(&s.name),
                                        escape_html(&disp),
                                        escape_html(&s.tone),
                                        pct,
                                        escape_html(&disp)
                                    )
                                })
                                .collect::<Vec<_>>()
                                .join("");
                            format!(
                                "<div class=\"openui-bar-row\"><div class=\"openui-bar-label\">{}</div><div class=\"openui-bar-group\">{}</div></div>",
                                escape_html_opt(Some(lbl)),
                                bars
                            )
                        })
                        .collect::<Vec<_>>()
                        .join("");
                    let cap_html = if is_truthy(caption) {
                        format!(
                            "<div class=\"openui-chart-caption\">{}</div>",
                            escape_html_opt(caption)
                        )
                    } else {
                        String::new()
                    };
                    format!(
                        "<div class=\"openui-barchart\" data-openui-component=\"BarChart\">{}{}</div>",
                        cap_html, rows
                    )
                }
                "AlertItem" => {
                    let tone = args
                        .first()
                        .filter(|v| is_truthy(Some(v)))
                        .map(|v| val_to_str(Some(v)))
                        .unwrap_or_else(|| "info".to_string());
                    let title = args.get(1);
                    let desc = args.get(2);
                    let meta = args.get(3);
                    let desc_html = if is_truthy(desc) {
                        format!(
                            "<div class=\"openui-alert-desc\">{}</div>",
                            escape_html_opt(desc)
                        )
                    } else {
                        String::new()
                    };
                    let meta_html = if is_truthy(meta) {
                        format!(
                            "<div class=\"openui-alert-meta\">{}</div>",
                            escape_html_opt(meta)
                        )
                    } else {
                        String::new()
                    };
                    format!(
                        "<div class=\"openui-alert tone-{}\" data-openui-component=\"AlertItem\"><div class=\"openui-alert-main\"><div class=\"openui-alert-title\">{}</div>{}</div>{}</div>",
                        escape_html(&tone),
                        escape_html_opt(title),
                        desc_html,
                        meta_html
                    )
                }
                "Checklist" => {
                    let items_raw: Vec<&Value> = match args.first() {
                        Some(Value::Array(arr)) => arr.iter().collect(),
                        Some(other) => vec![other],
                        None => vec![],
                    };
                    let rows = items_raw
                        .into_iter()
                        .filter(|it| {
                            it.get("$component").and_then(|v| v.as_str()) == Some("CheckItem")
                        })
                        .map(|it| {
                            let i_args = it
                                .get("args")
                                .and_then(|v| v.as_array())
                                .map(|v| v.as_slice())
                                .unwrap_or(&[]);
                            let label = i_args.first();
                            let ok = is_truthy(i_args.get(1));
                            let detail = i_args.get(2);
                            let cls = if ok { "pass" } else { "fail" };
                            let icon = if ok { "✓" } else { "✗" };
                            let detail_html = if is_truthy(detail) {
                                format!(
                                    "<span class=\"openui-check-detail\">{}</span>",
                                    escape_html_opt(detail)
                                )
                            } else {
                                String::new()
                            };
                            format!(
                                "<div class=\"openui-check-item {}\"><span class=\"openui-check-icon\">{}</span><div class=\"openui-check-body\"><span class=\"openui-check-label\">{}</span>{}</div></div>",
                                cls,
                                icon,
                                escape_html_opt(label),
                                detail_html
                            )
                        })
                        .collect::<Vec<_>>()
                        .join("");
                    format!(
                        "<div class=\"openui-checklist\" data-openui-component=\"Checklist\">{}</div>",
                        rows
                    )
                }
                "Badge" => {
                    let text = args.first();
                    let tone = args
                        .get(1)
                        .filter(|v| is_truthy(Some(v)))
                        .map(|v| val_to_str(Some(v)))
                        .unwrap_or_else(|| "neutral".to_string());
                    format!(
                        "<span class=\"openui-badge tone-{}\" data-openui-component=\"Badge\">{}</span>",
                        escape_html(&tone),
                        escape_html_opt(text)
                    )
                }
                "TextContent" => {
                    let text = args.first();
                    let variant = args
                        .get(1)
                        .filter(|v| is_truthy(Some(v)))
                        .map(|v| val_to_str(Some(v)))
                        .unwrap_or_else(|| "body".to_string());
                    format!(
                        "<p class=\"openui-text variant-{}\" data-openui-component=\"TextContent\">{}</p>",
                        escape_html(&variant),
                        escape_html_opt(text)
                    )
                }
                "CodeBlock" => {
                    let code = args.first();
                    let lang = args
                        .get(1)
                        .filter(|v| is_truthy(Some(v)))
                        .map(|v| val_to_str(Some(v)))
                        .unwrap_or_else(|| "text".to_string());
                    format!(
                        "<pre class=\"openui-code\" data-openui-component=\"CodeBlock\" data-lang=\"{}\"><code>{}</code></pre>",
                        escape_html(&lang),
                        escape_html_opt(code)
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

pub fn openui_literal(value: &Value) -> String {
    match value {
        Value::Null => "null".to_string(),
        Value::Bool(b) => (if *b { "true" } else { "false" }).to_string(),
        Value::Number(n) => {
            let s = n.to_string();
            if !s.contains('e') && !s.contains('E') {
                s
            } else {
                openui_str(&s)
            }
        }
        Value::String(s) => openui_str(s),
        other => openui_str(&other.to_string()),
    }
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

pub fn openui_f64(value: f64) -> String {
    if value.is_finite() {
        if value.abs() >= 1e21 || (value != 0.0 && value.abs() < 1e-6) {
            let exp = value.abs().log10().floor() as i32;
            let mantissa = value / 10_f64.powi(exp);
            let sign = if exp >= 0 { "+" } else { "" };
            return openui_str(&format!("{mantissa}e{sign}{exp}"));
        }
        let s = if value.fract() == 0.0 {
            format!("{}", value as i64)
        } else {
            format!("{value}")
        };
        if !s.contains('e') && !s.contains('E') {
            return s;
        }
        openui_str(&s)
    } else if value.is_nan() {
        openui_str("NaN")
    } else if value.is_sign_positive() {
        openui_str("Infinity")
    } else {
        openui_str("-Infinity")
    }
}

pub fn call(name: &str, args: &[String]) -> String {
    format!("{}({})", name, args.join(", "))
}

pub fn list(items: &[String]) -> String {
    format!("[{}]", items.join(", "))
}

pub fn to_openui_lang(state: &Value) -> String {
    let plugins = state
        .get("plugins")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let summary = state.get("summary").cloned().unwrap_or_else(|| json!({}));

    let total_catalog = summary
        .get("totalCatalog")
        .and_then(|v| v.as_i64())
        .unwrap_or_else(|| {
            plugins
                .iter()
                .filter(|p| {
                    p.get("inCatalog")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false)
                })
                .count() as i64
        });
    let installed_count = summary
        .get("installedCount")
        .and_then(|v| v.as_i64())
        .unwrap_or_else(|| {
            plugins
                .iter()
                .filter(|p| {
                    p.get("installed")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false)
                })
                .count() as i64
        });
    let enabled_count = summary
        .get("enabledCount")
        .and_then(|v| v.as_i64())
        .unwrap_or_else(|| {
            plugins
                .iter()
                .filter(|p| p.get("enabled").and_then(|v| v.as_bool()).unwrap_or(false))
                .count() as i64
        });
    let skills_count = summary
        .get("totalSkills")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let hooks_count = summary
        .get("totalHooks")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);

    let names: Vec<String> = plugins
        .iter()
        .map(|p| openui_str(p.get("name").and_then(|v| v.as_str()).unwrap_or("")))
        .collect();
    let versions: Vec<String> = plugins
        .iter()
        .map(|p| {
            let v = p.get("version").and_then(|v| v.as_str()).unwrap_or("—");
            let v = if v.is_empty() { "—" } else { v };
            openui_str(v)
        })
        .collect();
    let statuses: Vec<String> = plugins
        .iter()
        .map(|p| {
            let installed = p
                .get("installed")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            let enabled = p.get("enabled").and_then(|v| v.as_bool()).unwrap_or(false);
            if !installed {
                openui_str("Available")
            } else if enabled {
                openui_str("Enabled")
            } else {
                openui_str("Disabled")
            }
        })
        .collect();
    let capabilities: Vec<String> = plugins
        .iter()
        .map(|p| {
            let mut caps = Vec::new();
            let skills_len = p
                .get("skills")
                .and_then(|v| v.as_array())
                .map(|a| a.len())
                .unwrap_or(0);
            if skills_len > 0 {
                caps.push(format!("{skills_len} skill(s)"));
            }
            let hooks_len = p
                .get("hooks")
                .and_then(|v| v.as_array())
                .map(|a| a.len())
                .unwrap_or(0);
            if hooks_len > 0 {
                caps.push(format!("{hooks_len} hook(s)"));
            }
            if p.get("hasSidecar")
                .and_then(|v| v.as_bool())
                .unwrap_or(false)
            {
                caps.push("sidecar".to_string());
            }
            let joined = if caps.is_empty() {
                "—".to_string()
            } else {
                caps.join(" · ")
            };
            openui_str(&joined)
        })
        .collect();
    let descriptions: Vec<String> = plugins
        .iter()
        .map(|p| openui_str(p.get("description").and_then(|v| v.as_str()).unwrap_or("")))
        .collect();

    let header = call(
        "Header",
        &[
            openui_str("Extensions Marketplace"),
            openui_str("Antigravity Plugins"),
            openui_str(&format!("{enabled_count}/{total_catalog} enabled")),
            openui_str(if enabled_count > 0 {
                "success"
            } else {
                "neutral"
            }),
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
                        openui_str("Catalog Plugins"),
                        total_catalog.to_string(),
                        openui_str("First-party Vitruvian"),
                        openui_str("info"),
                    ],
                ),
                call(
                    "Kpi",
                    &[
                        openui_str("Installed"),
                        installed_count.to_string(),
                        openui_str("On local disk"),
                        openui_str("success"),
                    ],
                ),
                call(
                    "Kpi",
                    &[
                        openui_str("Enabled"),
                        enabled_count.to_string(),
                        openui_str("Active in config.json"),
                        openui_str("success"),
                    ],
                ),
                call(
                    "Kpi",
                    &[
                        openui_str("Skills & Hooks"),
                        (skills_count + hooks_count).to_string(),
                        openui_str(&format!("{skills_count} skills · {hooks_count} hooks")),
                        openui_str("info"),
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
                    &[openui_str("Plugin"), list(&names), openui_str("mono")],
                ),
                call(
                    "Col",
                    &[openui_str("Version"), list(&versions), openui_str("mono")],
                ),
                call("Col", &[openui_str("Status"), list(&statuses)]),
                call("Col", &[openui_str("Surfaces"), list(&capabilities)]),
                call("Col", &[openui_str("Description"), list(&descriptions)]),
            ]),
            openui_str("No plugins found in catalog."),
        ],
    );

    [
        "# ext-marketplace state as OpenUI Lang v0.5".to_string(),
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
    fn to_openui_lang_serialises_marketplace_state_and_compiles_to_html() {
        let state = json!({
            "plugins": [
                {
                    "name": "gh-watch",
                    "version": "1.6.0",
                    "installed": true,
                    "enabled": true,
                    "inCatalog": true,
                    "skills": ["gh-watch"],
                    "hooks": ["PostToolUse"],
                    "hasSidecar": true,
                    "description": "Watch GitHub PRs"
                }
            ],
            "summary": {
                "totalCatalog": 9,
                "installedCount": 9,
                "enabledCount": 9,
                "totalSkills": 9,
                "totalHooks": 12
            }
        });

        let dsl = to_openui_lang(&state);
        assert!(dsl.contains("root = Card([header, kpis, table])"));

        let parsed = parse_openui_lang(&dsl, None);
        assert_eq!(parsed.root["$component"], "Card");

        let html = compile_to_html(
            &dsl,
            &RenderOpts {
                title: Some("Extensions Marketplace".to_string()),
                ..Default::default()
            },
        );
        assert!(html.contains("Extensions Marketplace"));
        assert!(html.contains("gh-watch"));
        assert!(html.contains("Watch GitHub PRs"));
    }
}
